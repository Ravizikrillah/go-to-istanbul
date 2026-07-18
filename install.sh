#!/bin/sh
# go-to-istanbul — One-line Installer
# Usage: curl -sSL https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/install.sh | sh

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Banner ───────────────────────────────────────────────────────────────────

echo ""
echo "${BOLD}${CYAN}  ┌────────────────────────────────────────┐${RESET}"
echo "${BOLD}${CYAN}  │        go-to-istanbul installer        │${RESET}"
echo "${BOLD}${CYAN}  │  Go coverage → Istanbul HTML Report    │${RESET}"
echo "${BOLD}${CYAN}  └────────────────────────────────────────┘${RESET}"
echo ""

# ─── Prerequisite Checks ──────────────────────────────────────────────────────

check_cmd() {
  command -v "$1" > /dev/null 2>&1
}

if ! check_cmd node; then
  echo "${RED}❌  Node.js not found.${RESET}"
  echo "    Install Node.js (v18+) from: https://nodejs.org"
  exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo "${RED}❌  Node.js v18+ required. Current: $(node --version)${RESET}"
  echo "    Upgrade at: https://nodejs.org"
  exit 1
fi

if ! check_cmd npm; then
  echo "${RED}❌  npm not found. Please install npm.${RESET}"
  exit 1
fi

echo "${GREEN}✅  Node.js $(node --version) detected${RESET}"


# ─── Determine Install Mode ───────────────────────────────────────────────────
# Supports: --global (npm global install), --uninstall, or local project install (default)

INSTALL_MODE="local"
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --global|-g) INSTALL_MODE="global" ;;
    --uninstall) UNINSTALL=1 ;;
  esac
done

# ─── Uninstall Logic ──────────────────────────────────────────────────────────

if [ "$UNINSTALL" = "1" ]; then
  echo "${CYAN}🧹  Uninstalling go-to-istanbul...${RESET}"
  
  # 1. Global cleanup
  GLOBAL_BIN="/usr/local/bin/go-to-istanbul"
  GLOBAL_LIB_DIR="$HOME/.go-to-istanbul"
  
  if [ -f "$GLOBAL_BIN" ]; then
    echo "🗑️   Removing global binary: $GLOBAL_BIN"
    if [ ! -w "/usr/local/bin" ]; then
      sudo rm -f "$GLOBAL_BIN"
    else
      rm -f "$GLOBAL_BIN"
    fi
  fi
  
  if [ -d "$GLOBAL_LIB_DIR" ]; then
    echo "🗑️   Removing global library directory: $GLOBAL_LIB_DIR"
    rm -rf "$GLOBAL_LIB_DIR"
  fi

  # 2. Local cleanup (if run inside a project containing go-to-istanbul files)
  if [ -f "go-to-istanbul.js" ]; then
    echo "🗑️   Removing local go-to-istanbul.js"
    rm -f go-to-istanbul.js
  fi
  
  if [ -f "coverage.sh" ]; then
    echo "🗑️   Removing local coverage.sh"
    rm -f coverage.sh
  fi

  if [ -d "node_modules" ] && [ -f "package.json" ] && grep -q "istanbul-lib-report" "package.json" 2>/dev/null; then
    echo "🗑️   Removing local node_modules/"
    rm -rf node_modules
    echo "🗑️   Removing local package.json & package-lock.json"
    rm -f package.json package-lock.json
  fi

  # 3. Clean up .gitignore entries
  if [ -f ".gitignore" ]; then
    echo "📝  Cleaning up .gitignore..."
    # Create a temp file to filter out go-to-istanbul lines
    TMP_GI=$(mktemp /tmp/gti-gi-XXXXXX)
    
    # Filter out entries but keep others
    # This matches the pattern block we write during install
    # Uses a state machine (in sh) to skip the block from '# go-to-istanbul' down
    # through the lines we write.
    awk '
      /# go-to-istanbul/ { skip=1; next }
      skip && /^(node_modules\/|coverage\.out|coverage-report\/|\.nyc_output\/|go-to-istanbul\.js|coverage\.sh|package\.json|package-lock\.json)$/ { next }
      { skip=0; print }
    ' .gitignore > "$TMP_GI"
    
    cat "$TMP_GI" > .gitignore
    rm -f "$TMP_GI"
    
    # Remove trailing empty line if left at EOF
    if [ -s .gitignore ] && [ -z "$(tail -c 1 .gitignore)" ]; then
       # file ends with newline, check if double newline
       :
    fi
  fi

  echo "${GREEN}✅  Uninstall complete!${RESET}"
  exit 0
fi

# ─── Install ──────────────────────────────────────────────────────────────────


DEPS="istanbul-lib-coverage istanbul-lib-report istanbul-reports"

if [ "$INSTALL_MODE" = "global" ]; then
  # ─── Determine global bin path ─────────────────────────────────────────────
  GLOBAL_BIN="/usr/local/bin"
  if [ ! -w "$GLOBAL_BIN" ]; then
    echo "${YELLOW}⚠️   /usr/local/bin is not writable. Trying with sudo...${RESET}"
    USE_SUDO="sudo"
  else
    USE_SUDO=""
  fi

  GLOBAL_LIB_DIR="$HOME/.go-to-istanbul"

  echo "${CYAN}📦  Installing Istanbul dependencies globally...${RESET}"
  mkdir -p "$GLOBAL_LIB_DIR"
  npm install --prefix "$GLOBAL_LIB_DIR" $DEPS > /dev/null 2>&1

  echo "${CYAN}⬇️   Downloading go-to-istanbul script...${RESET}"
  curl -sSL \
    https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/index.js \
    -o "$GLOBAL_LIB_DIR/go-to-istanbul.js"

  # ── Create 2-phase global wrapper ──────────────────────────────────────────
  # Phase 1: if --run, handle spinner + go test entirely in shell
  # Phase 2: call node for Istanbul report generation
  $USE_SUDO tee "$GLOBAL_BIN/go-to-istanbul" > /dev/null << WRAPPER
#!/bin/sh
# go-to-istanbul — global wrapper (2-phase: shell spinner → node report)
LIB="$GLOBAL_LIB_DIR"

# ── Parse args ────────────────────────────────────────────────────────────────
SHOULD_RUN=0
INPUT="coverage.out"
PKG="./..."
COVERPKG=""

for _a in "\$@"; do
  case "\$_a" in
    --run|-r)  SHOULD_RUN=1 ;;
    --input)   : ;;  # value parsed below
    --pkg)     : ;;
    --coverpkg) : ;;
  esac
done

# Re-parse to get values for keyed args
_i=0
for _a in "\$@"; do
  _i=\$(( _i + 1 ))
  eval "_prev=\\\${_\$(( _i - 1 )):-}"
  case "\$_a" in
    --input)   _next_is_input=1 ;;
    --pkg)     _next_is_pkg=1 ;;
    --coverpkg) _next_is_coverpkg=1 ;;
    *)
      if [ "\${_next_is_input:-0}" = "1" ];   then INPUT="\$_a";   _next_is_input=0;   fi
      if [ "\${_next_is_pkg:-0}" = "1" ];     then PKG="\$_a";     _next_is_pkg=0;     fi
      if [ "\${_next_is_coverpkg:-0}" = "1" ]; then COVERPKG="\$_a"; _next_is_coverpkg=0; fi
      ;;
  esac
done

# ── Phase 1: run go test with shell spinner ───────────────────────────────────
if [ "\$SHOULD_RUN" = "1" ]; then
  COVERPKG_FLAG="\${COVERPKG:-\$PKG}"
  CMD="go test -coverpkg=\$COVERPKG_FLAG -coverprofile=\$INPUT \$PKG"
  TMP_OUT=\$(mktemp /tmp/go-to-istanbul-XXXXXX.log)

  # Braille spinner — identical to mosaic show_spinner
  _show_spinner() {
    _pid=\$1
    _msg=\$2
    # Use individual vars to avoid multi-byte cut issues
    _f0='⠋'; _f1='⠙'; _f2='⠹'; _f3='⠸'; _f4='⠼'
    _f5='⠴'; _f6='⠦'; _f7='⠧'; _f8='⠇'; _f9='⠏'
    tput civis 2>/dev/null
    _i=0
    while kill -0 "\$_pid" 2>/dev/null; do
      eval "_frame=\\\$_f\$(( _i % 10 ))"
      printf "\\r\\033[1;36m%s\\033[0m  %s" "\$_frame" "\$_msg"
      _i=\$(( _i + 1 ))
      sleep 0.08
    done
    printf "\\r\\033[K"
    tput cnorm 2>/dev/null
  }

  sh -c "\$CMD" > "\$TMP_OUT" 2>&1 &
  TEST_PID=\$!
  _show_spinner \$TEST_PID "Running Backend Unit Tests..."
  wait \$TEST_PID
  TEST_RC=\$?

  if [ \$TEST_RC -ne 0 ] || [ ! -f "\$INPUT" ]; then
    printf "❌  go test failed:\\n\\n"
    cat "\$TMP_OUT"
    rm -f "\$TMP_OUT"
    exit 1
  fi

  rm -f "\$TMP_OUT"
  printf "✅  Tests passed\\n\\n"
fi

# ── Phase 2: generate Istanbul report via Node.js (--run already handled) ─────
# Strip --run/-r from args so node doesn't try to re-run tests
_node_args=""
_skip_next=0
for _a in "\$@"; do
  if [ "\$_skip_next" = "1" ]; then _skip_next=0; continue; fi
  case "\$_a" in
    --run|-r) ;;  # drop
    *) _node_args="\$_node_args \$_a" ;;
  esac
done

NODE_PATH="\$LIB/node_modules" node "\$LIB/go-to-istanbul.js" \$_node_args
WRAPPER
  $USE_SUDO chmod +x "$GLOBAL_BIN/go-to-istanbul"


  echo "${GREEN}✅  Installed globally! Run from any folder with:${RESET}"
  echo "     ${YELLOW}go-to-istanbul --open${RESET}"
  echo "     ${YELLOW}go-to-istanbul --module \"github.com/user/repo/\" --open${RESET}"
else
  echo "${CYAN}📦  Installing Istanbul dependencies locally...${RESET}"
  npm install --save-dev $DEPS > /dev/null 2>&1

  echo "${CYAN}⬇️   Downloading go-to-istanbul script...${RESET}"
  curl -sSL \
    https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/index.js \
    -o go-to-istanbul.js

  chmod +x go-to-istanbul.js

  # Create convenience shell script
  cat > coverage.sh << 'EOF'
#!/bin/sh
# Runs Go tests with coverage and generates Istanbul HTML report

set -e

INPUT="${1:-coverage.out}"
OUTPUT="${2:-coverage-report}"
MODULE="${3:-}"

# Braille spinner — identical to mosaic show_spinner
_show_spinner() {
  _pid=$1
  _msg=$2
  _f0='⠋'; _f1='⠙'; _f2='⠹'; _f3='⠸'; _f4='⠼'
  _f5='⠴'; _f6='⠦'; _f7='⠧'; _f8='⠇'; _f9='⠏'
  tput civis 2>/dev/null
  _i=0
  while kill -0 "$_pid" 2>/dev/null; do
    eval "_frame=\$_f$(( _i % 10 ))"
    printf "\r\033[1;36m%s\033[0m  %s" "$_frame" "$_msg"
    _i=$(( _i + 1 ))
    sleep 0.08
  done
  printf "\r\033[K"
  tput cnorm 2>/dev/null
}

TMP_OUT=$(mktemp /tmp/go-to-istanbul-local-XXXXXX.log)

# Run go test silently in background
go test -coverpkg=./... -coverprofile="$INPUT" ./... > "$TMP_OUT" 2>&1 &
TEST_PID=$!

_show_spinner $TEST_PID "Running Backend Unit Tests..."
wait $TEST_PID
TEST_RC=$?

if [ $TEST_RC -ne 0 ] || [ ! -f "$INPUT" ]; then
  printf "❌  go test failed:\n\n"
  cat "$TMP_OUT"
  rm -f "$TMP_OUT"
  exit 1
fi

rm -f "$TMP_OUT"
printf "✅  Tests passed\n\n"

# Run go-to-istanbul.js converter (uses auto-detect module)
_args="-i $INPUT -o $OUTPUT -o"
if [ -n "$MODULE" ]; then
  _args="$_args -m $MODULE"
fi

node go-to-istanbul.js $_args
EOF


  chmod +x coverage.sh

  # ─── Update .gitignore ──────────────────────────────────────────────────────
  GITIGNORE_ENTRIES="
# go-to-istanbul
node_modules/
coverage.out
coverage-report/
.nyc_output/
go-to-istanbul.js
coverage.sh
package.json
package-lock.json"

  if [ -f .gitignore ]; then
    echo "${CYAN}📝  Updating .gitignore...${RESET}"
    # Append each entry only if it doesn't already exist
    for entry in node_modules/ coverage.out coverage-report/ .nyc_output/ go-to-istanbul.js coverage.sh package.json package-lock.json; do
      if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
      fi
    done

    # Add section header if not already present
    if ! grep -q "go-to-istanbul" .gitignore 2>/dev/null; then
      # Prepend the section to the top of what we just added — insert header before first new entry
      echo "" >> .gitignore
      printf "# go-to-istanbul\n" >> .gitignore
    fi
    echo "${GREEN}✅  .gitignore updated${RESET}"
  else
    echo "${CYAN}📝  Creating .gitignore...${RESET}"
    printf "%s\n" "$GITIGNORE_ENTRIES" > .gitignore
    echo "${GREEN}✅  .gitignore created${RESET}"
  fi

  echo "${GREEN}✅  Installation complete!${RESET}"
fi

# ─── Post-Install Instructions ────────────────────────────────────────────────

echo ""
echo "${BOLD}────────────────────────────────────────────${RESET}"
echo ""

if [ "$INSTALL_MODE" = "global" ]; then
  echo "${BOLD}  Quick Start:${RESET}"
  echo ""
  echo "  ${CYAN}1.${RESET} Run your Go tests with coverage:"
  echo "     ${YELLOW}go test -coverpkg=./internal/... -coverprofile=coverage.out ./...${RESET}"
  echo ""
  echo "  ${CYAN}2.${RESET} Generate Istanbul report:"
  echo "     ${YELLOW}go-to-istanbul${RESET}"
  echo ""
  echo "  ${CYAN}3.${RESET} Strip your module prefix (optional):"
  echo "     ${YELLOW}go-to-istanbul --module \"github.com/your/project/\"${RESET}"
else
  echo "${BOLD}  Quick Start:${RESET}"
  echo ""
  echo "  ${CYAN}Option A${RESET} — Run the all-in-one script:"
  echo "     ${YELLOW}./coverage.sh${RESET}"
  echo ""
  echo "  ${CYAN}Option B${RESET} — Step by step:"
  echo "     ${YELLOW}go test -coverpkg=./internal/... -coverprofile=coverage.out ./...${RESET}"
  echo "     ${YELLOW}node go-to-istanbul.js${RESET}"
  echo ""
  echo "  ${CYAN}With module prefix:${RESET}"
  echo "     ${YELLOW}node go-to-istanbul.js --module \"github.com/your/project/\"${RESET}"
  echo ""
  echo "  ${CYAN}Files created:${RESET}"
  echo "     📄  go-to-istanbul.js    — converter script"
  echo "     🐚  coverage.sh          — all-in-one runner"
fi

echo ""
echo "${BOLD}  Docs:${RESET} https://github.com/ravizikrillah/go-to-istanbul"
echo ""
