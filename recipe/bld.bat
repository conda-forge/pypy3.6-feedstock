set "PYPY3_SRC_DIR=%SRC_DIR%\pypy3"
set "PYTHON=%SRC_DIR%\pypy2-binary\pypy.exe"

REM PyPy translation looks for this.
set "PYPY_LOCALBASE=%PREFIX%"

set "GOAL_DIR=%PYPY3_SRC_DIR%\pypy\goal"
set "RELEASE_DIR=%PYPY3_SRC_DIR%\pypy\tool\release""

set "PYPY_PKG_NAME=pypy3"
set "BUILD_DIR=%PREFIX%\..\build"
set "TARGET_DIR=%PREFIX%\..\target"
set "ARCHIVE_NAME=%PYPY_PKG_NAME%-%PKG_VERSION%"

REM Build PyPy.
cd %GOAL_DIR%
REM This is what we would like to do
rem %PYTHON% ..\..\rpython\bin\rpython --make-jobs %CPU_COUNT% --shared -Ojit targetpypystandalone.py
rem But the machine runs out of memory, so break it into parts
rem -----------------
set "PYPY_USESSION_BASENAME=pypy3"
%PYTHON% ..\..\rpython\bin\rpython --no-compile --shared -Ojit targetpypystandalone.py
echo cd %TEMP%\usession-pypy3-0\testing_1 
cd %TEMP%\usession-pypy3-0\testing_1
nmake || exit /b 11
copy *.exe *.lib *.pdb %GOAL_DIR% || exit /b 11
cd %GOAL_DIR
rem -----------------

REM Build cffi imports using the generated PyPy.
set PYTHONPATH=..\..
%PYPY_PKG_NAME%-c ..\..\lib_pypy\pypy_tools\build_cffi_imports.py

REM Package PyPy.
cd %RELEASE_DIR%
mkdir %TARGET_DIR%

%PYTHON% package.py --targetdir="%TARGET_DIR%" --archive-name="%ARCHIVE_NAME%"

cd %TARGET_DIR%
unzip -xvf %ARCHIVE_NAME%.zip

REM Move all files from the package to conda's $PREFIX.
robocopy /S %TARGET_DIR%/%ARCHIVE_NAME%/* %PREFIX%

REM Move the generic file name to somewhere that's specific to pypy
move %PREFIX%\README.rst %PREFIX%\lib_pypy\
REM License is packaged separately
del %PREFIX%\LICENSE

REM Make sure the site-packages dir match with cpython
PY_VERSION=%name_suffix%
mkdir  %PREFIX%\lib\python%PY_VERSION%\site-packages
move %PREFIX%\site-packages\README %PREFIX%\lib\python%PY_VERSION%\site-packages\
rmdir /q /s %PREFIX%\site-packages
mklink /D %PREFIX%\lib\python%PY_VERSION%\site-packages %PREFIX%\site-packages

REM Build the cache for the standard library
timeout 60m pypy3 -m test --pgo -j%CPU_COUNT% || true;
cd %PREFIX%\lib-python
pypy3 -m compileall . || true;
cd %PREFIX%\lib_pypy
pypy3 -m compileall . || true;
