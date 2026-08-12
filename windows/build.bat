@echo off
echo ========================================
echo   轻图 Windows - 打包脚本
echo ========================================
echo.

echo [1/3] 安装 Python 依赖...
pip install -r requirements.txt
pip install pyinstaller

echo [2/3] 打包为 EXE...
pyinstaller --onefile --windowed --add-data "tools\posterize.exe;tools" --add-data "tools\oxipng.exe;tools" --name "轻图" --icon=NUL main.py

echo [3/3] 完成!
echo.
echo 输出文件: dist\轻图.exe
echo 将 tools 文件夹复制到 dist\ 目录下即可使用：
echo   xcopy /E /I tools dist\tools
pause
