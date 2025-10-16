#!/bin/bash

# Script to manually create a clang-format release from an LLVM tag
# Usage: ./scripts/create-release.sh <llvm-tag>
# Example: ./scripts/create-release.sh llvmorg-17.0.6

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <llvm-tag>"
    echo "Example: $0 llvmorg-17.0.6"
    exit 1
fi

LLVM_TAG="$1"
VERSION=${LLVM_TAG#llvmorg-}

echo "Creating release for LLVM tag: ${LLVM_TAG}"
echo "Version: ${VERSION}"

# Check if tag already exists
if git tag | grep -q "^${LLVM_TAG}$"; then
    echo "Error: Tag ${LLVM_TAG} already exists in repository"
    exit 1
fi

# Create working directory
mkdir -p "releases/${VERSION}"
cd "releases/${VERSION}"

# Define download URLs for different platforms
BASE_URL="https://github.com/llvm/llvm-project/releases/download/${LLVM_TAG}"

# Platform-specific download URLs and extraction
declare -A PLATFORMS=(
    ["linux-x64"]="clang+llvm-${VERSION}-x86_64-linux-gnu-ubuntu-20.04.tar.xz"
    ["linux-arm64"]="clang+llvm-${VERSION}-aarch64-linux-gnu.tar.xz"
    ["macos-x64"]="clang+llvm-${VERSION}-x86_64-apple-darwin.tar.xz"
    ["macos-arm64"]="clang+llvm-${VERSION}-arm64-apple-darwin22.0.tar.xz"
    ["windows-x64"]="LLVM-${VERSION}-win64.exe"
    ["windows-x86"]="LLVM-${VERSION}-win32.exe"
)

# Download and extract clang-format binaries
echo "Downloading and extracting clang-format binaries..."
extracted_count=0

for platform in "${!PLATFORMS[@]}"; do
    archive="${PLATFORMS[$platform]}"
    download_url="${BASE_URL}/${archive}"
    
    echo "Processing ${platform}: ${archive}"
    
    # Try to download the archive
    if curl -L -f -o "${archive}" "${download_url}"; then
        echo "  ✓ Downloaded ${archive}"
        
        # Extract clang-format binary based on file type
        if [[ "${archive}" == *.tar.xz ]]; then
            # Extract tar.xz files
            if tar -tf "${archive}" | grep -E 'bin/clang-format$' | head -1 > clang_format_path.txt && [ -s clang_format_path.txt ]; then
                clang_format_path=$(cat clang_format_path.txt)
                tar -xf "${archive}" "${clang_format_path}"
                cp "${clang_format_path}" "clang-format-${platform}"
                chmod +x "clang-format-${platform}"
                echo "  ✓ Extracted clang-format for ${platform}"
                ((extracted_count++))
            else
                echo "  ✗ Could not find clang-format in ${archive}"
            fi
        elif [[ "${archive}" == *.exe ]]; then
            # Extract Windows installer using 7zip or unzip
            if command -v 7z >/dev/null 2>&1; then
                7z x "${archive}" -o"windows_extract_${platform}" -y >/dev/null 2>&1 || true
                if find "windows_extract_${platform}" -name "clang-format.exe" | head -1 > clang_format_path.txt && [ -s clang_format_path.txt ]; then
                    clang_format_path=$(cat clang_format_path.txt)
                    cp "${clang_format_path}" "clang-format-${platform}.exe"
                    echo "  ✓ Extracted clang-format.exe for ${platform}"
                    ((extracted_count++))
                else
                    echo "  ✗ Could not find clang-format.exe in ${archive}"
                fi
                rm -rf "windows_extract_${platform}"
            else
                echo "  ✗ 7zip not available, skipping Windows extraction for ${platform}"
            fi
        fi
        
        # Clean up downloaded archive
        rm -f "${archive}"
        rm -f clang_format_path.txt
    else
        echo "  ✗ Failed to download ${archive}"
    fi
done

echo ""
echo "Extraction complete. Found ${extracted_count} clang-format binaries:"
ls -la clang-format-* 2>/dev/null || echo "No binaries found"

if [ ${extracted_count} -eq 0 ]; then
    echo "Error: No clang-format binaries were successfully extracted"
    exit 1
fi

# Create a tag in our repository
echo ""
echo "Creating git tag: ${LLVM_TAG}"
cd ../..
git tag -a "${LLVM_TAG}" -m "clang-format binaries from LLVM ${VERSION}"

echo "Tag created successfully. To push and create release, run:"
echo "  git push origin ${LLVM_TAG}"
echo ""
echo "Then create a GitHub release manually or use:"
echo "  gh release create ${LLVM_TAG} --title 'clang-format ${VERSION}' --notes 'Standalone clang-format binaries from LLVM ${VERSION}' releases/${VERSION}/clang-format-*"