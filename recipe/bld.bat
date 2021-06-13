echo on
set "PYPY3_SRC_DIR=%SRC_DIR%\pypy3"
set "PYTHON=%SRC_DIR%\pypy2-binary\pypy.exe"

REM PyPy translation looks for this.
set "PYPY_LOCALBASE=%PREFIX%"

set "GOAL_DIR=%PYPY3_SRC_DIR%\pypy\goal"
set "RELEASE_DIR=%PYPY3_SRC_DIR%\pypy\tool\release"

set "PYPY_PKG_NAME=pypy3"
set "BUILD_DIR=%PREFIX%\..\build"
set "TARGET_DIR=%PREFIX%\..\target"
set "ARCHIVE_NAME=%PYPY_PKG_NAME%-%PKG_VERSION%"

REM Build PyPy.
cd /d %GOAL_DIR%
REM This is what we would like to do
rem %PYTHON% ..\..\rpython\bin\rpython --make-jobs %CPU_COUNT% --shared -Ojit targetpypystandalone.py
rem But the machine runs out of memory, so break it into parts
rem -----------------
set "PYPY_USESSION_BASENAME=pypy3"
%PYTHON% ..\..\rpython\bin\rpython --no-compile --shared -Ojit targetpypystandalone.py
cd /d %TEMP%\usession-pypy3-0\testing_1 || exit /b 11
dir Makefile || exit /b 11
jom /f Makefile || exit /b 11
copy *.pdb %GOAL_DIR% 
copy *.dll %GOAL_DIR% 
copy *.exe %GOAL_DIR% 
rem TODO: parameterize this
copy libpypy3-c.lib %PYPY3_SRC_DIR%\libs\python37.lib || exit /b 11
cd /d %GOAL_DIR%
rem -----------------

REM Build cffi imports using the generated PyPy.
set PYTHONPATH=..\..
%PYPY_PKG_NAME%-c ..\..\lib_pypy\pypy_tools\build_cffi_imports.py
set PYTHONPATH=

REM Package PyPy.
mkdir %TARGET_DIR%

%PYTHON% %RELEASE_DIR%\package.py --builddir="%TARGETDIR%" --targetdir="%TARGET_DIR%" --archive-name="%ARCHIVE_NAME%"

REM Move all files from the package to conda's $PREFIX.
robocopy /S %TARGET_DIR%\%ARCHIVE_NAME% %PREFIX% || exit /b 11

REM Move the generic file name to somewhere that's specific to pypy
move %PREFIX%\README.rst %PREFIX%\lib_pypy\
REM License is packaged separately
del %PREFIX%\LICENSE

REM Make sure the site-packages dir match with cpython
set PY_VERSION=%name_suffix%
mkdir  %PREFIX%\lib\python%PY_VERSION%\site-packages
move %PREFIX%\site-packages\README %PREFIX%\lib\python%PY_VERSION%\site-packages\
rmdir /q /s %PREFIX%\site-packages
mklink /D %PREFIX%\site-packages %PREFIX%\lib\python%PY_VERSION%\site-packages || exit /b 11

REM Build the cache for the standard library
REM timeout 60m pypy3 -m test --pgo -j%CPU_COUNT% || true;
pypy3 -m test --pgo -j%CPU_COUNT%
cd %PREFIX%\lib-python
pypy3 -m compileall .
cd %PREFIX%\lib_pypy
pypy3 -m compileall .
REM TODO: fix the path to the pypy3 exe so the previous steps work.
REM In the mean time, do not fail
exit 0
