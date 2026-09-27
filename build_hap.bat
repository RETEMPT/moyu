@echo off
set "PATH=E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio\jbr\bin;%PATH%"
set "DEVECO_SDK_HOME=E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio\sdk"
call "E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --stop-daemon
call "E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default
