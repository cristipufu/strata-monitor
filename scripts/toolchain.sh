# Use the installed full Xcode toolchain without changing xcode-select globally.
# Its platform frameworks include Swift Testing, which some CLT installs omit.
if [[ -z "${DEVELOPER_DIR:-}" && -d '/Applications/Xcode.app/Contents/Developer' ]]; then
    export DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'
fi
