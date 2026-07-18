'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// ─── Helpers ──────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (err) {
    console.error(`  ❌ ${name}`);
    console.error(`     ${err.message}`);
    failed++;
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message || 'Assertion failed');
}

// ─── Test Setup ───────────────────────────────────────────────────────────────

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'go-to-istanbul-test-'));
const coverageFile = path.join(tmpDir, 'coverage.out');
const outputDir = path.join(tmpDir, 'coverage-report');

// Minimal Go coverage.out fixture
const fixtureCoverage = `mode: set
mosaic/internal/service/foo.go:12.34,15.10 3 1
mosaic/internal/service/foo.go:18.5,20.3 2 0
mosaic/internal/handler/bar.go:8.10,12.5 1 1
`;

fs.writeFileSync(coverageFile, fixtureCoverage);

// ─── Tests ────────────────────────────────────────────────────────────────────

console.log('\n🧪  go-to-istanbul tests\n');

test('should generate HTML report from coverage.out fixture', () => {
  const result = execSync(
    `node ${path.resolve(__dirname, '../index.js')} --input ${coverageFile} --output ${outputDir} --reporters html`,
    { encoding: 'utf8' },
  );
  assert(fs.existsSync(path.join(outputDir, 'index.html')), 'index.html not found');
  assert(result.includes('Istanbul report generated'), 'Success message not printed');
});

test('should strip module prefix from file paths', () => {
  const outputDir2 = path.join(tmpDir, 'coverage-report-2');
  execSync(
    `node ${path.resolve(__dirname, '../index.js')} --input ${coverageFile} --output ${outputDir2} --module "mosaic/" --reporters html`,
    { encoding: 'utf8' },
  );
  // Report should have been generated successfully
  assert(fs.existsSync(path.join(outputDir2, 'index.html')), 'index.html not found after stripping module prefix');
});

test('should exit with code 1 when coverage.out is missing', () => {
  try {
    execSync(
      `node ${path.resolve(__dirname, '../index.js')} --input /nonexistent/coverage.out`,
      { encoding: 'utf8', stdio: 'pipe' },
    );
    assert(false, 'Should have thrown');
  } catch (err) {
    assert(err.status === 1, `Expected exit code 1, got ${err.status}`);
  }
});

test('should print help and exit 0', () => {
  const result = execSync(
    `node ${path.resolve(__dirname, '../index.js')} --help`,
    { encoding: 'utf8' },
  );
  assert(result.includes('--input'), 'Help missing --input docs');
  assert(result.includes('--output'), 'Help missing --output docs');
  assert(result.includes('--module'), 'Help missing --module docs');
});

// ─── Cleanup ─────────────────────────────────────────────────────────────────

fs.rmSync(tmpDir, { recursive: true, force: true });

// ─── Summary ─────────────────────────────────────────────────────────────────

console.log(`\n${'─'.repeat(40)}`);
console.log(`  Total : ${passed + failed}`);
console.log(`  Passed: ${passed}`);
console.log(`  Failed: ${failed}`);
console.log(`${'─'.repeat(40)}\n`);

if (failed > 0) process.exit(1);
