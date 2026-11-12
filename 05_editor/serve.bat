@echo off
rem 本机起一个只读静态服务，根目录 = 仓库根（这样 index.html 里的 ../../03_Game_ds/assets 能取到图）
rem 用法：双击本文件，浏览器打开 http://localhost:8765/05_editor/index.html
cd /d "%~dp0\.."
set PORT=8765
where python >nul 2>nul
if %errorlevel%==0 (
  echo [editor] serving %CD% on http://localhost:%PORT%/05_editor/index.html
  start "" "http://localhost:%PORT%/05_editor/index.html"
  python -m http.server %PORT%
  goto :eof
)
where py >nul 2>nul
if %errorlevel%==0 (
  echo [editor] serving %CD% on http://localhost:%PORT%/05_editor/index.html
  start "" "http://localhost:%PORT%/05_editor/index.html"
  py -m http.server %PORT%
  goto :eof
)
echo [editor] 没找到 python，直接双击 index.html 也行（Chrome/Edge 支持文件授权）
pause
