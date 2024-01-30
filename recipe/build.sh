#!/bin/bash

set -exo pipefail

PYPY3_SRC_DIR=$SRC_DIR/pypy3

if [[ "$target_platform" == "osx-64" ]]; then
    export CC=$CLANG
    export PYTHON=${BUILD_PREFIX}/bin/python
fi

if [[ "$target_platform" == "linux"* ]]; then
   export CC=$GCC
   export PYTHON=${BUILD_PREFIX}/bin/python

   # Prevent linking to libncurses, forces libncursesw.
   rm -f ${PREFIX}/lib/libncurses.*

   # PyPy translation looks for this.
   export PYPY_LOCALBASE="$PREFIX"

   export LIBRARY_PATH=${PREFIX}/lib
   export C_INCLUDE_PATH=${PREFIX}/include
   export CPATH=${PREFIX}/include
fi

GOAL_DIR=$PYPY3_SRC_DIR/pypy/goal
RELEASE_DIR=$PYPY3_SRC_DIR/pypy/tool/release

PYPY_PKG_NAME=pypy3
BUILD_DIR=${PREFIX}/../build
TARGET_DIR=${PREFIX}/../target
export ARCHIVE_NAME="${PYPY_PKG_NAME}-${PKG_VERSION}"
export PYPY_PACKAGE_WITHOUTTK=1
export PYPY_NO_EMBED_DEPENDENCIES=1
export PYPY_NO_MAKE_PORTABLE=1

# Build PyPy in stages
# Force the build to use this directory
export PYPY_USESSION_BASENAME=pypy3
export PYPY_USESSION_DIR=${SRC_DIR}

cd $GOAL_DIR
${PYTHON} ../../rpython/bin/rpython --make-jobs ${CPU_COUNT} --no-compile --shared -Ojit targetpypystandalone.py
cd  ${SRC_DIR}/usession-pypy3-0/testing_1
make -j ${CPU_COUNT}
cp ${PYPY_PKG_NAME}* ${GOAL_DIR}
cp lib${PYPY_PKG_NAME}* ${GOAL_DIR}
cd $GOAL_DIR

if [[ "$target_platform" == "osx-64" ]]; then
    # Temporally set the @rpath of the generated PyPy binary to ${PREFIX}.
    cp ./${PYPY_PKG_NAME}*-c ./${PYPY_PKG_NAME}-c.bak
    ${INSTALL_NAME_TOOL} -add_rpath "${PREFIX}/lib" ./${PYPY_PKG_NAME}*-c
fi

# Build cffi imports using the generated PyPy.
PYTHONPATH=../.. ./${PYPY_PKG_NAME}*-c ../../lib_pypy/pypy_tools/build_cffi_imports.py

# Package PyPy.
cd $RELEASE_DIR
mkdir -p $TARGET_DIR

${PYTHON} ./package.py --targetdir="$TARGET_DIR" --archive-name="$ARCHIVE_NAME"

cd $TARGET_DIR
tar -xf $ARCHIVE_NAME.tar.bz2

# Move all files from the package to conda's $PREFIX.
cp -r $TARGET_DIR/$ARCHIVE_NAME/* $PREFIX

if [[ "$target_platform" == "osx-64" ]]; then
    # Move the dylib to lib folder.
    mv $PREFIX/bin/libpypy3*-c.dylib $PREFIX/lib/

    # Change @rpath to be relative to match conda's structure.
    ${INSTALL_NAME_TOOL} -rpath "${PREFIX}/lib" "@loader_path/../lib" $PREFIX/bin/pypy3
    rm $GOAL_DIR/${PYPY_PKG_NAME}-c.bak
fi


if [[ "$target_platform" == "linux"* ]]; then
    # Show links.
    ldd $PREFIX/bin/pypy3
    ldd $PREFIX/bin/libpypy3*-c.so

    # Move the so to lib folder.
    mv $PREFIX/bin/libpypy3*-c.so $PREFIX/lib/

    # Conda tries to `patchelf` this file, which fails.
    rm -f $PREFIX/bin/pypy3.debug
fi

# License is packaged separately
rm $PREFIX/LICENSE
PY_VERSION=$(echo $PKG_NAME | cut -c 5-)

# Make sure the site-packages dir match with cpython
mkdir -p $PREFIX/lib/python${PY_VERSION}/site-packages
mv $PREFIX/lib/pypy${PY_VERSION}/site-packages/README* $PREFIX/lib/python${PY_VERSION}/site-packages/
rm -rf $PREFIX/lib/pypy${PY_VERSION}/site-packages
ln -sf $PREFIX/lib/python${PY_VERSION}/site-packages $PREFIX/lib/pypy${PY_VERSION}/site-packages
pushd $PREFIX
pypy -m lib2to3.pgen2.driver lib/pypy${PY_VERSION}/lib2to3/Grammar.txt
pypy -m lib2to3.pgen2.driver lib/pypy${PY_VERSION}/lib2to3/PatternGrammar.txt
popd

# Regenerate the sysconfigdata__*.py file with paths from $PREFIX, at install
# those paths will be replaced with the actual user's paths. The generator
# builds the file in ./build/lib-<platform_tag>
host_gnu_type=$(${RELEASE_DIR}/config.guess)
pushd /tmp
pypy -m sysconfig --generate-posix-vars HOST_GNU_TYPE $host_gnu_type
cp build/*/_sysconfigdata*.py $PREFIX/lib/pypy${PY_VERSION}
sysconfigdata_name=$(basename $(ls build/*/_sysconfigdata*.py) | rev | cut -b 4- | rev)
popd

echo sysconfig $(pypy -c "from distutils import sysconfig; print(sysconfig)")
echo get_python_inc $(pypy -c "from distutils import sysconfig; print(sysconfig.get_python_inc())")
echo INCLUDEPY $(pypy -c "from distutils import sysconfig; print(sysconfig.get_config_var('INCLUDEPY'))")
ls $(pypy -c "from distutils import sysconfig; print(sysconfig.get_config_var('INCLUDEPY'))")

_PYTHON_SYSCONFIGDATA_NAME=$sysconfigdata_name pypy -c "from distutils import sysconfig; assert sysconfig.get_config_var('HOST_GNU_TYPE') != None"
# Run the python stdlib tests
# no timeout on darwin
# timeout 60m pypy3 -m test --pgo -j${CPU_COUNT} || true;


if [[ -d $PREFIX/lib_pypy ]]; then
    cd $PREFIX/lib-python
    pypy3 -m compileall . || true;
    cd $PREFIX/lib_pypy
    pypy3 -m compileall . || true;
else
    pypy3 -m compileall $PREFIX/lib/pypy${PY_VERSION} || true;
fi
# make sure all pypy3 processes are dead,
# somehow zombie processes cause problems later
pkill -9 pypy3 || true;
pkill -9 pypy || true;
