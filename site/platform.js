// Biết máy đang xem trước khi vẽ trang, để không hiện nhầm bản cài rồi mới đổi. ?for=android chọn thẳng một bản.
(function () {
  var ua = navigator.userAgent, root = document.documentElement;
  function detect() {
    // HarmonyOS 5 trở lên báo "OpenHarmony" và ArkWeb; HarmonyOS 4 trở xuống báo Android và cài được APK
    if (/OpenHarmony|ArkWeb/.test(ua)) return 'harmony';
    if (/Android/.test(ua)) return 'android';
    if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'iphone';
    if (/Macintosh|Mac OS X/.test(ua)) return 'mac';
    if (/Windows/.test(ua)) return 'windows';
    if (/Linux|X11|CrOS/.test(ua)) return 'linux';
    return 'other';
  }
  var detected = detect();
  var chosen = /[?&]for=(mac|android|harmony)(&|$)/.exec(location.search);
  root.dataset.detected = detected;
  root.dataset.platform = chosen ? chosen[1] : (/^(mac|android|harmony)$/.test(detected) ? detected : 'other');
})();
