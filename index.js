#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const https = require('https');

// ─── Version ──────────────────────────────────────────────────────────────────

const VERSION = '1.0.1';
const REPO_RAW = 'https://raw.githubusercontent.com/Ravizikrillah/go-to-istanbul/main';

// ─── Argument Parsing ─────────────────────────────────────────────────────────

const args = process.argv.slice(2);

function getArg(flags, defaultVal) {
  const flagList = Array.isArray(flags) ? flags : [flags];
  for (const flag of flagList) {
    const idx = args.indexOf(flag);
    if (idx !== -1 && args[idx + 1]) return args[idx + 1];
  }
  return defaultVal;
}

const coverageFile = getArg(['--input', '-i'], 'coverage.out');
const outputDir    = getArg(['--output', '-o'], 'coverage-report');
const reporters    = getArg(['--reporters', '-rep'], 'html,text-summary').split(',').map((r) => r.trim());

// Auto-detect module prefix from go.mod if --module not provided
function detectModulePrefix() {
  const explicit = getArg(['--module', '-m'], '');
  if (explicit) return explicit;

  // Walk up from cwd to find go.mod (supports running from subdirectory)
  let dir = process.cwd();
  for (let i = 0; i < 5; i++) {
    const gomod = path.join(dir, 'go.mod');
    if (fs.existsSync(gomod)) {
      const content = fs.readFileSync(gomod, 'utf8');
      const match   = content.match(/^module\s+(\S+)/m);
      if (match) {
        const mod = match[1].endsWith('/') ? match[1] : match[1] + '/';
        console.log(`🔍  Auto-detected module: ${mod.slice(0, -1)}`);
        return mod;
      }
    }
    const parent = path.dirname(dir);
    if (parent === dir) break; // reached filesystem root
    dir = parent;
  }
  return '';
}


const modulePrefix = detectModulePrefix();

const shouldOpen = args.includes('--open') || args.includes('-o');
const shouldRun = args.includes('--run') || args.includes('-r');
// ponytail: default coverpkg targets ./internal/... which is the common Go project convention
const testPkg = getArg(['--pkg', '-p'], './...');
const coverpkg = getArg(['--coverpkg', '-c'], '');


// ─── --version ────────────────────────────────────────────────────────────────

if (args.includes('--version') || args.includes('-v')) {
  console.log(`Local version: v${VERSION}`);

  // Fetch the latest raw index.js from GitHub to extract remote version
  const remoteUrl = `${REPO_RAW}/index.js`;
  
  const req = https.get(remoteUrl, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
      const match = data.match(/const VERSION = '([^']+)';/);
      if (match) {
        const latestVersion = match[1];
        console.log(`Latest GitHub version: v${latestVersion}`);
        if (latestVersion !== VERSION) {
          console.log(`\n📢  A new version is available (v${latestVersion}). Run: go-to-istanbul --update`);
        } else {
          console.log(`🟢  You are running the latest version.`);
        }
      }
      process.exit(0);
    });
  });

  req.on('error', () => {
    console.log(`Latest GitHub version: [Unable to fetch - offline]`);
    process.exit(0);
  });
  
  // Set timeout to avoid hanging if offline
  req.setTimeout(1500, () => {
    req.destroy();
    console.log(`Latest GitHub version: [Timeout checking for update]`);
    process.exit(0);
  });
}


// ─── --update ─────────────────────────────────────────────────────────────────

if (args.includes('--update')) {
  // Detect if running from global install (~/.go-to-istanbul) or local project
  const scriptPath = __filename;
  const globalLibDir = path.join(process.env.HOME || '', '.go-to-istanbul');
  const isGlobal = scriptPath.startsWith(globalLibDir);

  const targetPath = isGlobal
    ? path.join(globalLibDir, 'go-to-istanbul.js')
    : path.join(process.cwd(), 'go-to-istanbul.js');

  console.log(`\n🔄  Updating go-to-istanbul to latest version...`);
  console.log(`    Source : ${REPO_RAW}/index.js`);
  console.log(`    Target : ${targetPath}\n`);

  try {
    execSync(`curl -sSL ${REPO_RAW}/index.js -o "${targetPath}"`, { stdio: 'inherit' });
    console.log(`\n✅  Updated successfully! Run 'go-to-istanbul --version' to confirm.\n`);
  } catch {
    console.error('\n❌  Update failed. Check your internet connection and try again.\n');
    process.exit(1);
  }
  process.exit(0);
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
go-to-istanbul v${VERSION} — Convert Go coverage output to Istanbul HTML Report

Usage:
  go-to-istanbul [options]

Options:
  --input,      -i  Path to Go coverage file          (default: coverage.out)
  --output,     -o  Output directory for HTML report   (default: coverage-report)
  --module,     -m  Go module path prefix to strip     (e.g. "github.com/user/repo/")
  --reporters,-rep  Comma-separated Istanbul reporters (default: html,text-summary)
  --open,       -o  Open the HTML report in default browser after generation
  --run,        -r  Run go test automatically before generating the report
  --pkg,        -p  Package pattern passed to go test  (default: ./...)
  --coverpkg,   -c  Value for -coverpkg flag            (default: same as --pkg)
  --update          Update go-to-istanbul to the latest version from GitHub
  --version,    -v  Show current version
  --help,       -h  Show this help message

Examples:
  # Generate report from existing coverage.out
  go-to-istanbul -o

  # Run tests + generate report in one command (no manual go test needed!)
  go-to-istanbul -r -o

  # Run tests on specific packages + strip module prefix
  go-to-istanbul -r -p ./internal/... -m "github.com/user/project/" -o

  # Update to latest version
  go-to-istanbul --update

  # Custom input/output
  go-to-istanbul -i build/coverage.out -o reports/coverage
`);
  process.exit(0);
}

// ─── Dependencies ─────────────────────────────────────────────────────────────

let libCoverage, libReport, reports;
try {
  libCoverage = require('istanbul-lib-coverage');
  libReport = require('istanbul-lib-report');
  reports = require('istanbul-reports');
} catch (e) {
  console.error(
    '❌  Missing Istanbul dependencies. Run:\n' +
      '    npm install istanbul-lib-coverage istanbul-lib-report istanbul-reports\n',
  );
  process.exit(1);
}

// ─── Auto-run Go Tests ────────────────────────────────────────────────────────

if (shouldRun) {
  const { spawnSync } = require('child_process');
  const pkg = testPkg;
  const coverpkgFlag = coverpkg ? `-coverpkg=${coverpkg}` : `-coverpkg=${pkg}`;
  const cmd = `go test ${coverpkgFlag} -coverprofile=${coverageFile} ${pkg}`;

  // ── Braille spinner (same as mosaic show_spinner) ──────────────────────────
  const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  const CYAN  = '\x1b[1;36m';
  const RESET = '\x1b[0m';
  let frameIdx = 0;

  // Hide cursor
  process.stdout.write('\x1b[?25l');

  const spinner = setInterval(() => {
    const frame = frames[frameIdx++ % frames.length];
    process.stdout.write(`\r${CYAN}${frame}${RESET}  Running Backend Unit Tests...`);
  }, 80);

  // Run go test, capturing output — show only on failure
  const result = spawnSync('sh', ['-c', cmd], { encoding: 'utf8' });

  // Stop spinner, clear line, restore cursor
  clearInterval(spinner);
  process.stdout.write('\r\x1b[K');
  process.stdout.write('\x1b[?25h');

  if (result.status !== 0) {
    console.error('❌  go test failed:\n');
    if (result.stdout) process.stderr.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    console.error('\nFix test errors and try again.\n');
    process.exit(1);
  }

  console.log('✅  Tests passed\n');
}


// ─── Spinner Helper (shell-based, writes to /dev/tty to bypass buffering) ─────

function runWithSpinner(cmd, message, outputFile) {
  const { spawnSync } = require('child_process');
  const os = require('os');

  // Write script to a temp file so it runs as a real script (not sh -c arg)
  // Write all spinner output to /dev/tty directly — bypasses Node.js stdio buffering
  const scriptPath = path.join(os.tmpdir(), `gti-spinner-${Date.now()}.sh`);

  const shellScript = `#!/bin/sh
TMP_OUT="${outputFile}"
TTY=/dev/tty

# Run go test silently in background
sh -c ${JSON.stringify(cmd)} > "$TMP_OUT" 2>&1 &
CMD_PID=$!

SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
DELAY=0.08

tput civis > "$TTY" 2>/dev/null
i=0
while kill -0 "$CMD_PID" 2>/dev/null; do
  IDX=$(( (i % 10) + 1 ))
  FRAME=$(printf '%s' "$SPIN" | cut -c$IDX)
  printf "\\r\\033[1;36m%s\\033[0m  ${message}" "$FRAME" > "$TTY"
  i=$(( i + 1 ))
  sleep $DELAY
done

printf "\\r\\033[K" > "$TTY"
tput cnorm > "$TTY" 2>/dev/null

wait "$CMD_PID"
exit $?
`;

  fs.writeFileSync(scriptPath, shellScript, { mode: 0o755 });

  const result = spawnSync('sh', [scriptPath], {
    stdio: 'inherit',
  });

  try { fs.unlinkSync(scriptPath); } catch {}

  return { code: result.status ?? 1 };
}


// ─── Main ────────────────────────────────────────────────────────────────────

(async () => {

  // ── Auto-run Go Tests ────────────────────────────────────────────────────────

  if (shouldRun) {
    const os  = require('os');
    const pkg = testPkg;
    const coverpkgFlag = coverpkg ? `-coverpkg=${coverpkg}` : `-coverpkg=${pkg}`;
    const cmd = `go test ${coverpkgFlag} -coverprofile=${coverageFile} ${pkg}`;
    const tmpOut = path.join(os.tmpdir(), `go-to-istanbul-${Date.now()}.log`);

    const { code } = runWithSpinner(cmd, 'Running Backend Unit Tests...', tmpOut);

    if (code !== 0) {
      console.error('❌  go test failed:\n');
      try { process.stderr.write(fs.readFileSync(tmpOut, 'utf8')); } catch {}
      console.error('\nFix test errors and try again.\n');
      try { fs.unlinkSync(tmpOut); } catch {}
      process.exit(1);
    }

    try { fs.unlinkSync(tmpOut); } catch {}
    console.log('✅  Tests passed\n');
  }

  // ── Read Coverage File ───────────────────────────────────────────────────────

  if (!fs.existsSync(coverageFile)) {
    console.error(`❌  Coverage file not found: ${coverageFile}`);
    console.error(
      '    Tip: run tests automatically with:\n' +
        `    go-to-istanbul --run --open`,
    );
    process.exit(1);
  }

  const lines = fs.readFileSync(coverageFile, 'utf8').split('\n');
  const istanbulData = {};

  // ── Parse Go Coverage Format ─────────────────────────────────────────────────
  //
  // Go coverage line format:
  //   <file>:<startLine>.<startCol>,<endLine>.<endCol> <numStmts> <hitCount>
  //
  for (const line of lines) {
    if (!line || line.startsWith('mode:')) continue;

    const match = line.match(
      /^(.+):(\d+)\.(\d+),(\d+)\.(\d+) (\d+) (\d+)$/,
    );
    if (!match) continue;

    const [, file, startLine, startCol, endLine, endCol, numStmtsStr, countStr] =
      match;
    const count = parseInt(countStr, 10);
    const numStmts = parseInt(numStmtsStr, 10);

    // Strip module prefix so paths are relative and clean in the HTML report
    let filePath = file;
    if (modulePrefix && filePath.startsWith(modulePrefix)) {
      filePath = filePath.substring(modulePrefix.length);
    }

    if (!istanbulData[filePath]) {
      istanbulData[filePath] = {
        path: filePath,
        statementMap: {},
        s: {},
        fnMap: {},
        f: {},
        branchMap: {},
        b: {},
        _blockIdMap: {},
      };
    }

    const fileData = istanbulData[filePath];
    const blockKey = `${startLine}:${startCol}-${endLine}:${endCol}`;

    if (!fileData._blockIdMap[blockKey]) {
      fileData._blockIdMap[blockKey] = [];

      // Register each statement within this block
      for (let i = 0; i < numStmts; i++) {
        const statementIndex = String(Object.keys(fileData.statementMap).length + 1);
        fileData.statementMap[statementIndex] = {
          start: { line: parseInt(startLine, 10), column: parseInt(startCol, 10) },
          end: { line: parseInt(endLine, 10), column: parseInt(endCol, 10) },
        };
        fileData.s[statementIndex] = count;
        fileData._blockIdMap[blockKey].push(statementIndex);
      }
    } else {
      // Block already registered — accumulate hit counts
      for (const statementIndex of fileData._blockIdMap[blockKey]) {
        fileData.s[statementIndex] += count;
      }
    }
  }

  // ── Clean Internal Bookkeeping ───────────────────────────────────────────────

  for (const filePath in istanbulData) {
    delete istanbulData[filePath]._blockIdMap;
  }

  // ── Generate Istanbul Report ─────────────────────────────────────────────────

  const map = libCoverage.createCoverageMap(istanbulData);

  const context = libReport.createContext({
    dir: outputDir,
    defaultSummarizer: 'nested',
    coverageMap: map,
  });

  for (const reporter of reporters) {
    try {
      reports.create(reporter).execute(context);
    } catch (err) {
      console.warn(`⚠️  Reporter "${reporter}" failed: ${err.message}`);
    }
  }

  const reportPath = path.resolve(outputDir, 'index.html');

  console.log(`\n✅  Istanbul report generated at: ${reportPath}\n`);

  // ── Open in Browser ──────────────────────────────────────────────────────────

  if (shouldOpen) {
    const { execSync, spawnSync } = require('child_process');
    const platform = process.platform;
    const fileUrl = `file://${reportPath}`;

    // ponytail: try real browsers explicitly to avoid VSCode/editor hijacking .html
    const opened = (() => {
      if (platform === 'darwin') {
        const macBrowsers = [
          ['Google Chrome',  'com.google.Chrome'],
          ['Brave Browser',  'com.brave.Browser'],
          ['Firefox',        'org.mozilla.firefox'],
          ['Microsoft Edge', 'com.microsoft.edgemac'],
          ['Safari',         'com.apple.Safari'],
        ];
        for (const [name, bundle] of macBrowsers) {
          const check = spawnSync('open', ['-Ra', name], { stdio: 'pipe' });
          if (check.status === 0) {
            execSync(`open -a "${name}" "${fileUrl}"`);
            return name;
          }
        }
        // Last resort — OS default (may open VSCode if .html is associated)
        execSync(`open "${fileUrl}"`);
        return 'default app';
      } else if (platform === 'win32') {
        execSync(`start "" "${fileUrl}"`);
        return 'default browser';
      } else {
        // Linux / WSL — try common browsers first
        const linuxBrowsers = ['google-chrome', 'chromium-browser', 'firefox', 'xdg-open'];
        for (const bin of linuxBrowsers) {
          const check = spawnSync('which', [bin], { stdio: 'pipe' });
          if (check.status === 0) {
            spawnSync(bin, [fileUrl], { detached: true, stdio: 'ignore' });
            return bin;
          }
        }
        return null;
      }
    })();

    if (opened) {
      console.log(`🌐  Opened in ${opened}\n`);
    } else {
      console.warn(`⚠️  Could not open browser automatically. Open manually:\n    ${reportPath}\n`);
    }
  }

})();
