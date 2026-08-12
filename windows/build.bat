@echo off
echo ========================================
echo   轻图 Windows - 打包脚本
echo ========================================
echo.

echo [1/3] 安装 Python 依赖...
pip install -r requirements.txt
pip install pyinstaller

echo [2/3] 打包为 EXE...
pyinstaller --onefile --windowed --hidden-import customtkinter --collect-all customtkinter --add-data "tools\posterize.exe;tools" --add-data "tools\oxipng.exe;tools" --name "LiteImage" main.py

echo [3/3] 完成!
echo.
echo 输出文件: dist\LiteImage.exe
echo 将 tools 文件夹复制到 dist\ 目录下：
echo   xcopy /E /I tools dist\tools
echo.
echo 然后双击 dist\LiteImage.exe 即可运行
pause
