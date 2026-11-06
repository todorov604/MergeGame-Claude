@echo off
REM 以 540x960（设计尺寸 50%）直接启动预览，绕过编辑器 F5 带回的窗口尺寸。
cd /d "%~dp0"
start "" "E:\Program Files\Godot\Godot_v4.7.2.exe" --path "%~dp0"