@echo off
echo Starting compilation...
echo MetaEditor path: "C:\Program Files\PU Prime MT5 Terminal\MetaEditor64.exe"
echo File to compile: "%1"
echo Include path: "C:\Users\marth\AppData\Roaming\MetaQuotes\Terminal\E62C655ED163FFC555DD40DBEA67E6BB\MQL5"

"C:\Program Files\PU Prime MT5 Terminal\MetaEditor64.exe" /compile:"%1" /inc:"C:\Users\marth\AppData\Roaming\MetaQuotes\Terminal\E62C655ED163FFC555DD40DBEA67E6BB\MQL5" /log

if exist "%~dp1%~n1.log" (
    type "%~dp1%~n1.log"
    del "%~dp1%~n1.log"
)

echo Compilation finished
