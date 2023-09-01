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
set PYPY_PACKAGE_NO_DLLS=1

REM Report system info
systeminfo

REM this will do more frequent collections but may make translation pass?
set PYPY_GC_MAX_DELTA=400MB

REM Build PyPy.
cd /d %GOAL_DIR%
REM This is what we would like to do
rem %PYTHON% ..\..\rpython\bin\rpython --make-jobs %CPU_COUNT% --shared -Ojit targetpypystandalone.py
rem But the machine runs out of memory, so break it into parts
rem -----------------
set PYPY_USESSION_BASENAME=pypy3
set PYPY_USESSION_DIR=%SRC_DIR%
%PYTHON% ..\..\rpython\bin\rpython --no-compile --shared -Ojit targetpypystandalone.py
cd /d %SRC_DIR%\usession-pypy3-0\testing_1 || exit /b 11
dir Makefile || exit /b 11
jom /f Makefile || exit /b 11

set PY_VERSION=%name_suffix%

for /F "tokens=1,2 delims=." %%i in ("%PY_VERSION%") do (
  set "PY_VERSION_NODOTS=%%i%%j"
)

copy /b *.pdb %GOAL_DIR%
copy /b *.dll %GOAL_DIR%
copy /b *.exe %GOAL_DIR%
REM lib goes elsewhere
copy /b *.lib %PYPY3_SRC_DIR%\libs\python%PY_VERSION_NODOTS%.lib || exit /b 11

cd /d %GOAL_DIR%

REM Package PyPy.
mkdir %TARGET_DIR%

%PYTHON% %RELEASE_DIR%\package.py --builddir="%TARGET_DIR%" --targetdir="%TARGET_DIR%" --archive-name="%ARCHIVE_NAME%"
IF %ERRORLEVEL% NEQ 0 (Echo ERROR while packaging &exit /b 11)

REM Move all files from the package to conda's $PREFIX.
robocopy /S %TARGET_DIR%\%ARCHIVE_NAME% %PREFIX% /njh /njs /np /ndl /nc /ns
IF %ERRORLEVEL% LSS 8 goto ROBOCOPYOK
echo problem with robocopy
exit /b 11
:ROBOCOPYOK

REM License is packaged separately
del %PREFIX%\LICENSE

REM create an executable that runs adddlldirectory
REM before loading the pypy DLL
del %PREFIX%\pypy.exe
cl /O2 %RECIPE_DIR%\pypy_win.c /Fe%PREFIX%\pypy.exe "/DPY_VER=\"%PY_VERSION%\""

cd %PREFIX%\Lib
..\pypy3 -m lib2to3.pgen2.driver lib2to3\Grammar.txt
IF %ERRORLEVEL% NEQ 0 (Echo ERROR while compiling &exit /b 11)
..\pypy3 -m lib2to3.pgen2.driver lib2to3\PatternGrammar.txt
IF %ERRORLEVEL% NEQ 0 (Echo ERROR while compiling &exit /b 11)
rem still in lib-python or Lib

..\pypy3 -m compileall .
rem do not check error, some of the files have syntax errors on purpose

cd %PREFIX%

REM TODO: figure out a way to run these tests in a reasonable time
REM On the PyPy buildbot (4 cores) they require ~30 minutes, here they
REM take 4 hours. Using --timeout=100 does not work, the kill makes the
REM process hang
REM timeout 60m pypy3 -m test --pgo -j%CPU_COUNT% || true;

REM Build the cache for the standard library
pypy -c "import _testcapi"
IF %ERRORLEVEL% NEQ 0 (Echo ERROR while building &exit /b 11)
if "%PY_VERSION%" == "3.8" (
    pypy -c "import _ctypes_test"
    IF %ERRORLEVEL% NEQ 0 (Echo ERROR while building &exit /b 11)
    pypy -c "import _testmultiphase"
) else (
    pypy -c "import _ctypes_test_build"
    IF %ERRORLEVEL% NEQ 0 (Echo ERROR while building &exit /b 11)
    pypy -c "import _testmultiphase_build"
)
IF %ERRORLEVEL% NEQ 0 (Echo ERROR while building &exit /b 11)

REM Include a %PREFIX%\Scripts directory in the package. This ensures
REM that entry_points are able to be created by downstream packages.
if not exist "%PREFIX%\Scripts" mkdir "%PREFIX%\Scripts"
copy /y NUL "%PREFIX%\Scripts\.keep"
if errorlevel 1 exit 1

REM Test that the dlls are still accesable when using a venv
set CONDA_DLL_SEARCH_MODIFICATION_DEBUG=1
pypy -c "import sqlite3"
pypy -m venv destination
destination\Scripts\python -c "import sqlite3"
if errorlevel 1 exit 1
rmdir /q /s destination

REM Copy required DLLs so pypy can be used without activating the environment
REM This would fix issue #101 but did not pass reivew
REM copy /b %PREFIX%\Library\bin\libexpat.dll %PREFIX%
REM copy /b %PREFIX%\Library\bin\libbz2.dll %PREFIX%
REM copy /b %PREFIX%\Library\bin\ffi-8.dll %PREFIX%
