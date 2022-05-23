# Copyright (C) 2020 Jan Weiß
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# NOTE: Shell script variable names are enclosed in curly braces when used. Xcode variables are not! Their $ is also escaped (\$) in regex.

PROJECT_NAME="libzip"

CMAKE_PROJECT_RELATIVE_PATH="External/lipzip"
CMAKE_PROJECT_ASSCENTION_PATH="../../"
CMAKE_RELATIVE_SOURCE_ROOT="${CMAKE_PROJECT_RELATIVE_PATH}/lib"

CLEAN_CMAKE_ARTEFACTS_ON_EVERY_RUN=0

# From: https://stackoverflow.com/a/3572105
realpath() {
	[[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

ROOT_DIR=$(dirname $(realpath "$0"))
#echo "ROOT_DIR: ${ROOT_DIR}"

MACOS_SDK_ROOT=$(xcrun --sdk macosx --show-sdk-path)
#echo "MACOS_SDK_ROOT: ${MACOS_SDK_ROOT}"

CMAKE_PROJECT_ROOT="${ROOT_DIR}/${CMAKE_PROJECT_RELATIVE_PATH}"
#echo "CMAKE_PROJECT_ROOT: ${CMAKE_PROJECT_ROOT}"
cd "$CMAKE_PROJECT_ROOT"

#cmake --build "${CMAKE_PROJECT_ASSCENTION_PATH}" --target clean # This doesn’t seem to work for us.
# Do cleanup manually:
if [ $CLEAN_CMAKE_ARTEFACTS_ON_EVERY_RUN -eq 1 ]; then
	echo "Deleting CMakeFiles"
	rm -R "${ROOT_DIR}/CMakeFiles"
	echo "Deleting CMakeScripts"
	rm -R "${ROOT_DIR}/CMakeScripts"
	echo "Deleting *.cmake"
	rm "${ROOT_DIR}/*.cmake"
fi

cmake -G "Xcode" -B "${CMAKE_PROJECT_ASSCENTION_PATH}" \
-D "CMAKE_OSX_ARCHITECTURES=\$(ARCHS_STANDARD)" \
-D "CMAKE_OSX_SYSROOT=macosx" \
-D "CMAKE_OSX_DEPLOYMENT_TARGET=10.9" \
-D "ENABLE_ZSTD=OFF" \
-D "ENABLE_MBEDTLS=OFF" \
-D "ENABLE_OPENSSL=OFF" \
-D "BUILD_TOOLS=OFF" \
-D "BUILD_REGRESS=OFF" \
-D "BUILD_EXAMPLES=OFF" \
-D "BUILD_DOC=OFF" \

cd "${ROOT_DIR}/${PROJECT_NAME}.xcodeproj"
#cp -p project.pbxproj project-before.pbxproj


# Find the main group ID
MAIN_GROUP_ID=$(perl -0777 -nle 'm:\t*mainGroup = ([0-9A-F]+):; print "$1\n"' project.pbxproj)
#echo "MAIN_GROUP_ID: ${MAIN_GROUP_ID}"


# Patch project to relative paths.
sed \
-e "s:${MACOS_SDK_ROOT}:\$SDKROOT:g" \
-e "s:HEADER_SEARCH_PATHS = (\"${ROOT_DIR}/${CMAKE_RELATIVE_SOURCE_ROOT}\",\"${ROOT_DIR}\");:HEADER_SEARCH_PATHS = (\"\$\(SRCROOT\)/${CMAKE_RELATIVE_SOURCE_ROOT}\",\"\$\(SRCROOT\)\");:g" \
-e "s:${ROOT_DIR}/${CMAKE_RELATIVE_SOURCE_ROOT}:${CMAKE_RELATIVE_SOURCE_ROOT}:g" \
-e "s:${ROOT_DIR}:\$PROJECT_FILE_PATH/..:g" \
-i '' project.pbxproj


# Fix projectDirPath. 
# This also controls the build directory, if it’s relative to the project and not in the global Xcode build directory.
sed \
-e "s:projectDirPath = ${CMAKE_PROJECT_RELATIVE_PATH};:projectDirPath = \"\";:g" \
-e "s:sourceTree = SOURCE_ROOT;:sourceTree = \"<group>\";:g" \
-i '' project.pbxproj

# Loop through the child IDs and add/set path.
CHILD_ID_LIST=$(perl -0777 -nle 'm:\t*'"${MAIN_GROUP_ID}"'\Q = {\E.*?\Qchildren = (\E(.*?)\Q);\E.*?\Q};\E:s; print "$1\n"' project.pbxproj)
PRODUCTS_ID=$(perl -0777 -nle 'm:([0-9A-F]+)[^\n]*?\Q = {\E[^}]*?\Qname = Products;\E:; print "$1\n"' project.pbxproj)

#echo "CHILD_ID_LIST: ${CHILD_ID_LIST}"
while IFS= read -r
do
	# TODO Skip "Products"
	CHILD_ID=$(echo "${REPLY}" | perl -nle 'm/\t*([0-9A-F]+)/; print $1')
	[ -z "${CHILD_ID}" ] && continue
	[ "${PRODUCTS_ID}" = "${CHILD_ID}" ] && continue
	#echo "CHILD_ID: ${CHILD_ID}"
	# Set child group to CMake root:
	perl -i -pe 's:('"${CHILD_ID}"'[^\n]*?\Q = {\E):\1\npath = "'"${CMAKE_PROJECT_RELATIVE_PATH}"'";:g' project.pbxproj
done <<< "$CHILD_ID_LIST"
# Set main group to root:
perl -i -pe 's:('"${MAIN_GROUP_ID}"'\Q = {\E):\1\npath = "";:g' project.pbxproj


# Patch project to default to spaces for indentation.
perl -i -pe 's:('"${MAIN_GROUP_ID}"'\Q = {\E):\1\nusesTabs = 0;:g' project.pbxproj

# Remove all scripts.
# NOTE: Pretty crude, but works for now. Could be done more elegantly by getting the IDs for the “CMake PostBuild Rules” and removing only those.
perl -i -pe 'BEGIN{undef $/;} s:\Q/* Begin PBXShellScriptBuildPhase section */\E.*?\Q/* End PBXShellScriptBuildPhase section */\E\n*::smg' project.pbxproj
perl -i -pe "s:\w*[0-9A-F]+(\Q /* CMake PostBuild Rules */,\E\n)::g" project.pbxproj

perl -i -pe 'BEGIN{undef $/;} s:\Q/* Begin PBXBuildStyle section */\E.*?\Q/* End PBXBuildStyle section */\E\n*::smg' project.pbxproj
perl -i -pe "s:\w*[0-9A-F]+(\Q /* CMake Rules */,\E\n)::g" project.pbxproj


# Patch install path.
sed \
-e 's:INSTALL_PATH = "";:INSTALL_PATH = "@rpath";:g' \
-e 's:PRODUCT_NAME = zip.*;:PRODUCT_NAME = "$(TARGET_NAME)";:g' \
-e 's:-install_name @rpath/.*\.dylib::g' \
-i '' project.pbxproj


# Patch Build Products Path.
sed \
-e 's:SYMROOT = .*;::g' \
-i '' project.pbxproj


# Patch dylib target to framework.
# NOTE: Incomplete. Doesn’t work.
#sed \
#-e 's:name = zip;:name = ${PROJECT_NAME};:g' \
#-e 's:productName = zip;:productName = ${PROJECT_NAME};:g' \
#-e 's:productType = "com.apple.product-type.library.dynamic";:productType = "com.apple.product-type.framework";:g' \
#-e 's:DYLIB_COMPATIBILITY_VERSION = .*?;:DYLIB_COMPATIBILITY_VERSION = 1;:g' \
#-e 's:DYLIB_CURRENT_VERSION = .*?;:DYLIB_CURRENT_VERSION = 1;:g' \
#-e 's:EXECUTABLE_PREFIX = lib;:FRAMEWORK_VERSION = A;:g' \
#-e 's:EXECUTABLE_SUFFIX = .dylib;:EXECUTABLE_SUFFIX = .framework;:g' \
#-e 's:INSTALL_PATH = "@rpath";:INFOPLIST_FILE = Info.plist;\0' \
#PRODUCT_BUNDLE_IDENTIFIER = "at.nih.\$\{PRODUCT_NAME\:rfc1034identifier\}";:g' \
#-i '' project.pbxproj

#perl -i -pe 's:\Q/* zip */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.dylib"; path = ${PROJECT_NAME}.dylib; sourceTree = BUILT_PRODUCTS_DIR; };\E:/* ${PROJECT_NAME}.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = ${PROJECT_NAME}.framework; sourceTree = BUILT_PRODUCTS_DIR; };:g' project.pbxproj

# framework Info.plist support MISSING!
# framework header file support MISSING!

#				CODE_SIGN_IDENTITY = "-";
#				DEBUG_INFORMATION_FORMAT = dwarf;
#				LD_RUNPATH_SEARCH_PATHS = "@loader_path/";


# Fix signing issues.
#sed -i '' 's:ARCHS = "$(ARCHS_STANDARD)";:ARCHS = "$(ARCHS_STANDARD)";\
#CODE_SIGN_IDENTITY = "Apple Development";\
#CODE_SIGN_STYLE = Manual;:g' project.pbxproj

#cp -p project.pbxproj project-after.pbxproj

