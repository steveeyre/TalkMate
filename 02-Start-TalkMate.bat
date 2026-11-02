@echo off
setlocal
cd /d "%~dp0"
call :main
set "MAINERR=%ERRORLEVEL%"
echo.
pause
exit /b %MAINERR%

:main
echo ============================================
echo  TalkMate start (App + Whisper + TTS + LLM)
echo ============================================
echo Folder: %CD%

if not exist "%CD%\scripts\start-all.ps1" (
  echo.
  echo ERROR: scripts\start-all.ps1 not found.
  echo Unzip the full package first.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\scripts\start-all.ps1" -BindHost 0.0.0.0
set "PSERR=%ERRORLEVEL%"
if not "%PSERR%"=="0" (
  echo.
  echo Start FAILED with code %PSERR%.
  exit /b %PSERR%
)

echo.
echo Open on this PC: http://127.0.0.1:8080/
echo On your phone (same Wi-Fi): use the LAN URL printed above.
echo LLM:  http://127.0.0.1:11434/  (Ollama API)
exit /b 0
