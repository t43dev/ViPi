package dev.t43.vipi

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Tự cập nhật từ GitHub Releases, cùng cách với bản Mac: lấy danh sách release, tải APK, chỉ cài khi APK đúng package,
 * số phiên bản cao hơn và cùng chữ ký với app đang chạy. Đây là phần duy nhất của app dùng mạng; không gửi gì về chữ đã gõ.
 */
object Updater {
    sealed class State {
        object Idle : State()
        object Checking : State()
        object UpToDate : State()
        data class Available(val version: String) : State()
        data class Downloading(val version: String) : State()
        data class Ready(val version: String) : State()
        data class Installing(val version: String) : State()
        data class Failed(val message: String) : State()
    }

    private class Release(val version: String, val url: String)

    private const val TAG = "ViPiUpdate"
    private const val JOB_ID = 7301
    private const val FEED = "https://api.github.com/repos/t43dev/ViPi/releases?per_page=30"
    private const val TAG_PREFIX = "android-v"
    private const val MAX_APK = 64L * 1024 * 1024
    private const val CHANNEL = "updates"
    private const val NOTIFICATION_ID = 1
    private const val FEED_KEY = "update_feed" // chỉ bản debug: nguồn release giả để kiểm thử
    const val EXTRA_INSTALL = "install"

    @Volatile var state: State = State.Idle
        private set
    var onChange: (() -> Unit)? = null
    var foreground: Activity? = null
    @Volatile private var release: Release? = null
    @Volatile private var waitingForPermission = false
    private val busy = AtomicBoolean()
    private val main = Handler(Looper.getMainLooper())

    private fun set(s: State) {
        state = s
        main.post { onChange?.invoke() }
    }

    fun currentVersion(context: Context): String =
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"

    private fun debuggable(context: Context) = BuildConfigCompat.debuggable(context)

    /** Bản debug: `adb shell am start ... -e feed http://...` trỏ tới nguồn thử; bản phát hành không đọc gì khác ngoài GitHub. */
    fun useTestFeed(context: Context, url: String?) {
        if (debuggable(context) && url != null) Prefs(context).sp.edit().putString(FEED_KEY, url).apply()
    }

    private fun feed(context: Context): String? {
        if (!debuggable(context)) return FEED
        return Prefs(context).sp.getString(FEED_KEY, null) // bản debug ký khoá khác: không tự lấy bản thật
    }

    /** Một lần mỗi ngày khi có mạng. Không dùng job bền qua khởi động lại: dịch vụ bàn phím chạy lại sau boot và đặt lại. */
    fun schedule(context: Context) {
        if (feed(context) == null) return
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (scheduler.getPendingJob(JOB_ID) != null) return
        scheduler.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(context, UpdateJobService::class.java))
                .setPeriodic(24 * 3600 * 1000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(15 * 60 * 1000L, JobInfo.BACKOFF_POLICY_LINEAR)
                .build()
        )
    }

    // MARK: - Người dùng bấm

    fun check(context: Context) {
        if (!busy.compareAndSet(false, true)) return
        set(State.Checking)
        thread(name = "vipi-update") {
            try {
                val found = fetchNewer(context)
                release = found
                set(if (found == null) State.UpToDate else State.Available(found.version))
            } catch (e: Exception) {
                Log.w(TAG, "check failed", e)
                set(State.Failed("Could not reach GitHub. Check your connection and try again."))
            } finally {
                busy.set(false)
            }
        }
    }

    fun install(activity: Activity) {
        if (!activity.packageManager.canRequestPackageInstalls()) {
            waitingForPermission = true
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return
        }
        if (!busy.compareAndSet(false, true)) return
        val context = activity.applicationContext
        thread(name = "vipi-update") {
            try {
                val r = release ?: fetchNewer(context) ?: run {
                    set(State.UpToDate)
                    return@thread
                }
                release = r
                val apk = fetchApk(context, r)
                set(State.Installing(r.version))
                commit(context, apk)
            } catch (e: Exception) {
                Log.w(TAG, "install failed", e)
                set(State.Failed(e.message?.takeIf { e is UpdateRejected } ?: "Could not download the update. Try again."))
            } finally {
                busy.set(false)
            }
        }
    }

    /** Vừa bật quyền cài ứng dụng trong Cài đặt rồi quay lại: cài tiếp. */
    fun resume(activity: Activity) {
        if (waitingForPermission && activity.packageManager.canRequestPackageInstalls()) {
            waitingForPermission = false
            install(activity)
        }
    }

    // MARK: - Chạy nền

    /** `done(true)`: thử lại sau (bàn phím đang mở). Lỗi mạng thì để lần kiểm tra ngày mai. */
    fun background(context: Context, done: (Boolean) -> Unit) {
        if (!busy.compareAndSet(false, true)) { done(false); return }
        thread(name = "vipi-update") {
            var retry = false
            try {
                retry = backgroundStep(context)
            } catch (e: Exception) {
                Log.w(TAG, "background update failed", e)
                set(State.Idle)
            } finally {
                busy.set(false)
                done(retry)
            }
        }
    }

    private fun backgroundStep(context: Context): Boolean {
        val r = fetchNewer(context)
        release = r
        if (r == null) {
            apkDir(context).deleteRecursively()
            set(State.Idle)
            return false
        }
        set(State.Available(r.version))
        val metered = context.getSystemService(ConnectivityManager::class.java).isActiveNetworkMetered
        if (metered && !apkFile(context, r).exists()) return false // không tiêu dữ liệu di động khi người dùng chưa bấm
        val apk = fetchApk(context, r)
        if (ViPiInputMethod.keyboardVisible) return true
        if (context.packageManager.canRequestPackageInstalls()) {
            set(State.Installing(r.version))
            commit(context, apk)
        } else {
            val open = Intent(context, SettingsActivity::class.java).putExtra(EXTRA_INSTALL, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            notify(context, r.version, open)
        }
        return false
    }

    // MARK: - GitHub

    private fun fetchNewer(context: Context): Release? {
        val url = feed(context) ?: return null
        val c = URL(url).openConnection() as HttpURLConnection
        val body = try {
            c.connectTimeout = 15_000
            c.readTimeout = 20_000
            c.setRequestProperty("Accept", "application/vnd.github+json")
            c.setRequestProperty("User-Agent", "ViPi-Android/${currentVersion(context)}")
            check(c.responseCode == 200) { "HTTP ${c.responseCode}" }
            c.inputStream.bufferedReader().use { it.readText() }
        } finally {
            c.disconnect()
        }
        val current = currentVersion(context)
        val list = JSONArray(body)
        var best: Release? = null
        for (i in 0 until list.length()) {
            val o = list.getJSONObject(i)
            val tag = o.getString("tag_name")
            if (o.optBoolean("draft") || !tag.startsWith(TAG_PREFIX)) continue
            val assets = o.getJSONArray("assets")
            for (j in 0 until assets.length()) {
                val a = assets.getJSONObject(j)
                if (!a.getString("name").endsWith(".apk")) continue
                val version = tag.removePrefix(TAG_PREFIX)
                if (best == null || isNewer(version, best.version)) best = Release(version, a.getString("browser_download_url"))
                break
            }
        }
        return best?.takeIf { isNewer(it.version, current) }
    }

    fun isNewer(a: String, b: String): Boolean {
        val parts = { s: String -> s.split('.').map { p -> p.takeWhile(Char::isDigit).toIntOrNull() ?: 0 } }
        val x = parts(a)
        val y = parts(b)
        for (i in 0 until maxOf(x.size, y.size)) {
            val u = x.getOrElse(i) { 0 }
            val v = y.getOrElse(i) { 0 }
            if (u != v) return u > v
        }
        return false
    }

    // MARK: - Tải và kiểm

    private class UpdateRejected(message: String) : Exception(message)

    private fun apkDir(context: Context) = File(context.cacheDir, "update")
    private fun apkFile(context: Context, r: Release) = File(apkDir(context), "ViPi-${r.version}.apk")

    private fun fetchApk(context: Context, r: Release): File {
        val apk = apkFile(context, r)
        if (!apk.exists()) {
            set(State.Downloading(r.version))
            apk.parentFile!!.apply { deleteRecursively(); mkdirs() }
            val part = File(apk.path + ".part")
            val c = URL(r.url).openConnection() as HttpURLConnection
            try {
                c.connectTimeout = 15_000
                c.readTimeout = 30_000
                c.setRequestProperty("User-Agent", "ViPi-Android/${currentVersion(context)}")
                check(c.responseCode == 200) { "HTTP ${c.responseCode}" }
                var total = 0L
                c.inputStream.use { input ->
                    part.outputStream().use { out ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            total += n
                            check(total <= MAX_APK) { "APK too large" }
                            out.write(buffer, 0, n)
                        }
                    }
                }
                check(c.contentLengthLong < 0 || c.contentLengthLong == total) { "Truncated download" }
            } finally {
                c.disconnect()
            }
            part.renameTo(apk)
        }
        try {
            verify(context, apk)
        } catch (e: UpdateRejected) {
            apk.delete()
            throw e
        }
        set(State.Ready(r.version))
        return apk
    }

    private fun verify(context: Context, apk: File) {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val update = pm.getPackageArchiveInfo(apk.path, flags) ?: throw UpdateRejected("The download is not a valid app.")
        val installed = pm.getPackageInfo(context.packageName, flags)
        if (update.packageName != context.packageName) throw UpdateRejected("The download is a different app.")
        if (code(update) <= code(installed)) throw UpdateRejected("The download is not newer than this version.")
        val a = signers(update)
        if (a.isEmpty() || a != signers(installed)) throw UpdateRejected("The download is not signed by the ViPi developer.")
    }

    private fun code(p: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) p.longVersionCode else @Suppress("DEPRECATION") p.versionCode.toLong()

    private fun signers(p: PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= 28) p.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") p.signatures
        return certs.orEmpty().map { c ->
            MessageDigest.getInstance("SHA-256").digest(c.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    // MARK: - Cài

    private fun commit(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            // Android 12+: từ lần ViPi tự cài đầu tiên trở đi hệ thống không cần hỏi lại
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val status = PendingIntent.getBroadcast(context, id, Intent(context, UpdateReceiver::class.java), flags)
            session.commit(status.intentSender)
        }
    }

    internal fun installStatus(context: Context, intent: Intent) {
        val version = release?.version ?: ""
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = @Suppress("DEPRECATION") intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                val activity = foreground
                if (activity != null) activity.startActivity(confirm)
                else {
                    notify(context, version, confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    set(State.Ready(version)) // chờ người dùng; mở Cài đặt vẫn bấm cài được
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                apkDir(context).deleteRecursively()
                set(State.Idle)
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> set(State.Ready(version))
            else -> {
                Log.w(TAG, "install status: " + intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
                set(State.Failed("Android could not install the update. Try again."))
            }
        }
    }

    private fun notify(context: Context, version: String, open: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Updates", NotificationManager.IMPORTANCE_DEFAULT))
        val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(
            NOTIFICATION_ID,
            Notification.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("ViPi $version is ready")
                .setContentText("Tap to install.")
                .setContentIntent(tap)
                .setAutoCancel(true)
                .build()
        )
    }
}

/** Kết quả từ PackageInstaller. */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Updater.installStatus(context, intent)
}

/** Kiểm tra mỗi ngày; tắt "Install updates automatically" thì không ra mạng. */
class UpdateJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        if (!Prefs(this).autoUpdate) return false
        Updater.background(this) { retry -> jobFinished(params, retry) }
        return true
    }

    override fun onStopJob(params: JobParameters) = true
}
