@echo off
setlocal
REM 预览启动器（50% / 540x960）。Godot 探测顺序：
REM   1) 本目录或上一级的 godot_path.txt（换机器改那一行即可）
REM   2) 环境变量 GODOT   3) PATH 里的 godot.exe   4) 常见安装目录
cd /d "%~dp0"
set "GODOT_EXE="
if exist "%~dp0godot_path.txt" for /f "usebackq delims=" %%L in ("%~dp0godot_path.txt") do if not defined GODOT_EXE if exist "%%~L" set "GODOT_EXE=%%~L"
if not defined GODOT_EXE if exist "%~dp0..\godot_path.txt" for /f "usebackq delims=" %%L in ("%~dp0..\godot_path.txt") do if not defined GODOT_EXE if exist "%%~L" set "GODOT_EXE=%%~L"
if not defined GODOT_EXE if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"
if not defined GODOT_EXE for /f "delims=" %%P in ('where godot.exe 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%P"
if not defined GODOT_EXE for %%D in (
    "%ProgramFiles%\Godot\Godot_v4.7.2.exe"
    "%ProgramFiles%\Godot\godot.exe"
    "%ProgramFiles%\Godot Engine\godot.exe"
    "%LOCALAPPDATA%\Programs\Godot\godot.exe"
  ) do if not defined GODOT_EXE if exist %%D set "GODOT_EXE=%%~D"
if not defined GODOT_EXE (
  echo [run_preview] 找不到 Godot：在本目录或上一级新建 godot_path.txt，写入 godot.exe 的完整路径。
  pause
  exit /b 1
)
echo [run_preview] Godot = %GODOT_EXE%
start "" "%GODOT_EXE%" --path "%~dp0" -- --preview=0.5