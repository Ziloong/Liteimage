@echo off
echo ========================================
echo   轻图 Windows - 打包脚本 (Flet)
echo ========================================
echo.

echo [1/2] 安装 Python 依赖...
pip install -r requirements.txt

echo [2/2] 打包为 EXE（Flet 方式）...
flet pack main.py --name LiteImage --add-data "tools;tools"

echo.
echo 完成！输出: dist\LiteImage.exe
echo 注意：ffmpeg.exe(84MB) 已一并打包，EXE 体积较大
pause
