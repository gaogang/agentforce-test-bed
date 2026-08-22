import { promises as fs } from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const BASE_CONFIG_PATH = path.join(ROOT, 'config', 'agent-settings.json');
const LOCAL_CONFIG_PATH = path.join(ROOT, 'config', 'agent-settings.local.json');
const BUNDLES_DIR = path.join(ROOT, 'force-app', 'main', 'default', 'aiAuthoringBundles');
const DEFAULT_USER_PATTERN = /^(\s*default_agent_user:\s*)"([^"]*)"\s*$/m;

function getArgFlag(flag) {
  return process.argv.includes(flag);
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        return walk(fullPath);
      }
      return fullPath;
    })
  );
  return files.flat();
}

function updateAgentContent(content, defaultAgentUser) {
  if (!DEFAULT_USER_PATTERN.test(content)) {
    return { updated: false, content };
  }

  const next = content.replace(DEFAULT_USER_PATTERN, `$1"${defaultAgentUser}"`);
  return { updated: next !== content, content: next };
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function loadDefaultAgentUser() {
  const baseRaw = await fs.readFile(BASE_CONFIG_PATH, 'utf8');
  const baseConfig = JSON.parse(baseRaw);
  let defaultAgentUser = (baseConfig.defaultAgentUser || '').trim();
  let source = 'base';

  if (!getArgFlag('--base-only') && (await fileExists(LOCAL_CONFIG_PATH))) {
    const localRaw = await fs.readFile(LOCAL_CONFIG_PATH, 'utf8');
    const localConfig = JSON.parse(localRaw);
    const localDefaultAgentUser = (localConfig.defaultAgentUser || '').trim();
    if (localDefaultAgentUser) {
      defaultAgentUser = localDefaultAgentUser;
      source = 'local';
    }
  }

  if (!defaultAgentUser) {
    throw new Error('config/agent-settings.json must define a non-empty defaultAgentUser value.');
  }

  return {
    defaultAgentUser,
    source,
    baseDefaultAgentUser: (baseConfig.defaultAgentUser || '').trim()
  };
}

function readAgentDefaultUser(content) {
  const match = content.match(DEFAULT_USER_PATTERN);
  return match ? match[2] : null;
}

async function verifySafeState(agentPaths, safeDefaultAgentUser) {
  const offenders = [];
  for (const agentPath of agentPaths) {
    const content = await fs.readFile(agentPath, 'utf8');
    const currentDefault = readAgentDefaultUser(content);
    if (currentDefault !== null && currentDefault !== safeDefaultAgentUser) {
      offenders.push({
        path: path.relative(ROOT, agentPath),
        currentDefault
      });
    }
  }

  if (offenders.length === 0) {
    console.log('Safe check passed: all .agent files use the base defaultAgentUser value.');
    return;
  }

  console.error('Safe check failed: these .agent files contain a non-base default_agent_user value:');
  for (const offender of offenders) {
    console.error(`- ${offender.path}: ${offender.currentDefault}`);
  }
  console.error('Run "npm run agent:reset-config" before committing.');
  process.exit(1);
}

async function main() {
  const { defaultAgentUser, source, baseDefaultAgentUser } = await loadDefaultAgentUser();

  const allPaths = await walk(BUNDLES_DIR);
  const agentPaths = allPaths.filter((p) => p.endsWith('.agent'));

  if (getArgFlag('--verify-safe')) {
    await verifySafeState(agentPaths, baseDefaultAgentUser);
    return;
  }

  let changed = 0;
  for (const agentPath of agentPaths) {
    const original = await fs.readFile(agentPath, 'utf8');
    const result = updateAgentContent(original, defaultAgentUser);
    if (result.updated) {
      await fs.writeFile(agentPath, result.content, 'utf8');
      changed += 1;
      console.log(`Updated ${path.relative(ROOT, agentPath)}`);
    }
  }

  console.log(`Using ${source} config defaultAgentUser.`);

  if (changed === 0) {
    console.log('No .agent files needed updates.');
    return;
  }

  console.log(`Applied defaultAgentUser to ${changed} .agent file(s).`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
