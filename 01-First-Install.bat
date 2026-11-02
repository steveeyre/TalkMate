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
echo  TalkMate first-time setup
echo ============================================
echo Folder: %CD%

if not exist "%CD%\scripts\setup-first-run.ps1" (
  echo.
  echo ERROR: scripts\setup-first-run.ps1 not found.
  echo Unzip the FULL TalkMate-Portable.zip to a real folder first.
  echo Do not run from inside a zip preview / temp folder.
  exit /b 1
)

echo Running setup via PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\scripts\setup-first-run.ps1"
set "PSERR=%ERRORLEVEL%"
if not "%PSERR%"=="0" (
  echo.
  echo Setup FAILED with code %PSERR%.
  echo Fix the errors above, then run 01 again.
  exit /b %PSERR%
)

echo.
echo Setup finished successfully.
echo Next: run 02-Start-TalkMate.bat
exit /b 0
