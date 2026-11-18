#!/bin/zsh
# Run ON the Mac Studio: zsh ~/Harmony/mac_release.sh. Builds ~/Harmony/vipi-agc (rsync of harmony/ from HQ-01) with the AGC release cert/profile in ~/Harmony/signing -> ~/Harmony/dist/vipi-<ver>-release.app
set -e
D=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$D/sdk JAVA_HOME=$D/jbr/Contents/Home VIPI_RESOURCES=$HOME/Harmony/Resources
export PATH=$JAVA_HOME/bin:$D/tools/node/bin:$D/tools/ohpm/bin:$D/tools/hvigor/bin:$PATH
K=$HOME/Harmony/signing
B=$HOME/Harmony/vipi-release-build
rm -rf $B; mkdir -p $B; rsync -a --exclude build --exclude .hvigor $HOME/Harmony/vipi-agc/ $B/
PW=$(cat $K/vipi-keystore.pwd.enc)
python3 - "$B/build-profile.json5" "$K" "$PW" <<'PY'
import sys,re
p,k,pw=sys.argv[1:]
s=open(p).read()
cfg='''"signingConfigs": [{"name": "default", "type": "HarmonyOS", "material": {"certpath": "%s/vipi-release.cer", "keyAlias": "vipi", "keyPassword": "%s", "profile": "%s/vipi-release.p7b", "signAlg": "SHA256withECDSA", "storeFile": "%s/vipi-keystore.p12", "storePassword": "%s"}}]''' % (k,pw,k,k,pw)
s2=s.replace('"signingConfigs": []',cfg,1)
assert s2!=s
open(p,'w').write(s2)
PY
cd $B
ohpm install --all >/dev/null
hvigorw --mode project -p product=default -p buildMode=release assembleApp --no-daemon 2>&1 | grep -E "ERROR|BUILD|SignApp|SignHap" | grep -v WARN
mkdir -p $HOME/Harmony/dist
V=$(python3 -c "import re;print(re.search(r'\"versionName\": \"([^\"]+)\"',open('AppScope/app.json5').read()).group(1))")
OUT=$HOME/Harmony/dist/vipi-$V-release.app
cp build/outputs/default/*-default-signed.app $OUT
rm -rf /tmp/vipi-verify; mkdir /tmp/vipi-verify; cd /tmp/vipi-verify; unzip -q $OUT
for h in *.hap; do java -jar $D/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar verify-app -inFile $h -outCertChain c.cer -outProfile p.p7b 2>&1 | grep -iE "success|fail"; done
ls -la $OUT
