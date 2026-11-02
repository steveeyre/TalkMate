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
echo  TalkMate stop (App + Whisper + TTS)
echo ============================================

if not exist "%CD%\scripts\stop-all.ps1" (
  echo.
  echo ERROR: scripts\stop-all.ps1 not found.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\scripts\stop-all.ps1"
set "PSERR=%ERRORLEVEL%"
if not "%PSERR%"=="0" (
  echo.
  echo Stop FAILED with code %PSERR%.
  exit /b %PSERR%
)
exit /b 0
