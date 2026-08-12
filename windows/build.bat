@echo off
echo ========================================
echo   轻图 Windows - 打包脚本 (Flet)
echo ========================================
echo.

echo [1/2] 安装 Python 依赖...
pip install -r requirements.txt

echo [2/2] 打包为 EXE（Flet 方式）...
flet pack main.py --name LiteImage --add-data "tools;tools" --icon NUL

echo.
echo 完成！输出: dist\LiteImage.exe
echo 确保 tools 文件夹在 exe 同目录下
pause
