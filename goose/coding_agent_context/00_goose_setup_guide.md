# 🪿 Goose Agent Setup — Complete Run Book

> **Author:** Auto-generated from tobmenne's working setup  
> **Last updated:** 2026-03-06  
> **Estimated time:** 30–45 minutes

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install Goose CLI](#2-install-goose-cli)
3. [Add Goose to Your PATH](#3-add-goose-to-your-path)
4. [Set Up AWS Credentials](#4-set-up-aws-credentials)
5. [Start an Ongoing ADA Credential Refresh Job](#5-start-an-ongoing-ada-credential-refresh-job)
6. [Export AWS Environment Variables](#6-export-aws-environment-variables)
7. [Verify Bedrock Access](#7-verify-bedrock-access)
8. [Configure Goose](#8-configure-goose)
9. [Hello World Test with Goose (Anthropic Model)](#9-hello-world-test-with-goose-anthropic-model)
10. [Install Builder-MCP](#10-install-builder-mcp)
11. [Configure Builder-MCP in Goose](#11-configure-builder-mcp-in-goose)
12. [Hello World Test with Builder-MCP](#12-hello-world-test-with-builder-mcp)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

Before you begin, make sure you have the following:

- **A Cloud Desktop or Amazon Linux dev environment** with shell access (bash)
- **Active Midway credentials** (for toolbox and internal tooling)
- **An AWS account** with Bedrock access (you will need an account ID, role name, and provider)
- **`curl`** installed (verify with `curl --version`)
- **`tar`** installed (verify with `tar --version`)
- **`ada`** (Amazon's credential helper) installed and available in your PATH
- **`toolbox`** (Builder Toolbox) installed and available in your PATH
  - Verify: `toolbox --version`
  - If not installed, see internal docs for Builder Toolbox installation

---

## 2. Install Goose CLI

Run the official Goose installation script:

```bash
# Install via official script
curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | console=yes sh
```

The installer will:
1. Detect your OS and architecture
2. Download the latest stable `goose` binary
3. Install it to `$HOME/.local/bin/` (the default `GOOSE_BIN_DIR`)
4. Run `goose configure` interactively — **you can skip this for now** (we will configure manually in [Step 8](#8-configure-goose))

After installation, verify goose is installed:

```bash
# Verify
goose --version
```

You should see output similar to:
```
 1.21.0
```

> **Note:** If the `goose` command is not found, proceed to Step 3 to add it to your PATH.

### 2.1 Trouble shooting (Installation fails on dev desktop)

On your dev desktop, the installation might fail with the follwoing error:

```
curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | console=yes sh
WINDIR: <not set>
OSTYPE: linux-gnu
uname -s: Linux
uname -m: x86_64
PWD: /home/tobmenne/work/20260306_installGoose
Detected OS: linux with ARCH x86_64
Downloading stable release: goose-x86_64-unknown-linux-gnu.tar.bz2...
Extracting goose-x86_64-unknown-linux-gnu.tar.bz2 to temporary directory...
Moving goose to /home/tobmenne/.local/bin/goose

Configuring goose

/home/tobmenne/.local/bin/goose: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.25' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.26' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libm.so.6: version `GLIBC_2.27' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libm.so.6: version `GLIBC_2.29' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libc.so.6: version `GLIBC_2.27' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libc.so.6: version `GLIBC_2.28' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libc.so.6: version `GLIBC_2.29' not found (required by /home/tobmenne/.local/bin/goose)
/home/tobmenne/.local/bin/goose: /lib64/libc.so.6: version `GLIBC_2.30' not found (required by /home/tobmenne/.local/bin/goose)
[tobmenne@dev-dsk-tobmenne-1d-5ae3a81a 20260306_installGoose]$ goose --version
goose: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.25' not found (required by goose)
goose: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.26' not found (required by goose)
goose: /lib64/libm.so.6: version `GLIBC_2.27' not found (required by goose)
goose: /lib64/libm.so.6: version `GLIBC_2.29' not found (required by goose)
goose: /lib64/libc.so.6: version `GLIBC_2.27' not found (required by goose)
goose: /lib64/libc.so.6: version `GLIBC_2.28' not found (required by goose)
goose: /lib64/libc.so.6: version `GLIBC_2.29' not found (required by goose)
goose: /lib64/libc.so.6: version `GLIBC_2.30' not found (required by goose)
```

If that happens, try to compile goose from scratch. We will need a conda environment to make that happen:


```
wget https://repo.anaconda.com/miniconda/Miniconda3-py312_24.7.1-0-Linux-x86_64.sh
bash Miniconda3-py312_24.7.1-0-Linux-x86_64.sh -b -p $HOME/miniconda3
eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
conda init bash
```

#### Create the Minimal Environment

Save this as `goose-build-env.yml`:

```yaml
name: goose-build
channels:
  - conda-forge
dependencies:
  # === Rust toolchain ===
  - rust                    # provides cargo + rustc + activation script for linker

  # === C/C++ compilers (sets CC, CXX, CFLAGS, LDFLAGS automatically) ===
  - compilers               # meta-package: gcc, g++, gfortran + activation scripts
  - make                    # GNU make

  # === Native libraries required by goose crates ===
  - dbus                    # libdbus-1 (for xcap + keyring/dbus-secret-service)
  - libxcb                  # libxcb (for xcap screen capture)
  - xorg-libx11             # libX11 (X11 support)
  - xorg-libxau             # libXau (X11 auth)
  - xorg-libxdmcp           # libXdmcp (X11 display manager)
  - xorg-libxext            # libXext
  - xorg-libxfixes          # libXfixes
  - xorg-libxrandr          # libXrandr
  - xorg-libxrender         # libXrender
  - openssl                 # libssl + libcrypto (for keyring/dbus-secret-service)
  - zlib                    # libz
  - libsqlite               # SQLite (for sqlx crate)

  # === Build support ===
  - pkg-config              # helps some crates find libraries (optional but recommended)
```

Create it:

```
conda env create -f goose-build-env.yml
```

#### Build Goose

```
conda activate goose-build

# CRITICAL: conda does NOT set PKG_CONFIG_PATH automatically!
# Some Rust crates (libdbus-sys, openssl-sys) use pkg-config to find libraries.
# Without this, they may fail or fall back to vendored/system versions.
export PKG_CONFIG_PATH="$CONDA_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

conda install -c conda-forge libclang
conda install -c conda-forge cmake

GCC_BUILTIN=$(find $CONDA_PREFIX/lib/gcc -path "*/include/stdbool.h" ! -path "*/c++/*" -printf '%h\n' | head -1)
SYSROOT_INCLUDE="$CONDA_PREFIX/x86_64-conda-linux-gnu/sysroot/usr/include"
export BINDGEN_EXTRA_CLANG_ARGS="-isystem $GCC_BUILTIN -isystem $SYSROOT_INCLUDE -isystem $CONDA_PREFIX/include"

git clone https://github.com/block/goose.git
cd goose
cargo build --release -p goose-cli --no-default-features
```

---

## 3. Add Goose to Your PATH

The goose installer places the binary in `$HOME/.local/bin/`. If this directory is not already in your `PATH`, you need to add it.

### Step 3.1 — Check if it's already in your PATH

```bash
echo $PATH | tr ':' '\n' | grep '.local/bin'
```

If you see a line like `/home/<your-alias>/.local/bin`, you're good — skip to [Step 4](#4-set-up-aws-credentials).

### Step 3.2 — Add to your shell profile

Determine your shell:

```bash
echo $SHELL
```

Then edit the appropriate file:

| Shell  | File to Edit        |
|--------|---------------------|
| bash   | `~/.bashrc`         |
| zsh    | `~/.zshrc`          |

Add the following line **at the end** of the file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

For example, if you use **bash**:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### Step 3.3 — Reload your shell

```bash
source ~/.bashrc
# or for zsh:
# source ~/.zshrc
```

### Step 3.4 — Verify

```bash
which goose
goose --version
```

Expected output:
```
/home/<your-alias>/.local/bin/goose
 1.21.0
```

---

## 4. Set Up AWS Credentials

You need to configure an AWS credentials profile that uses `ada` to dynamically obtain credentials via `credential_process`. This allows Goose to authenticate with AWS Bedrock.

### Step 4.1 — Create the `credential_process` profile in `~/.aws/credentials`

Open (or create) the file `~/.aws/credentials`:

```bash
mkdir -p ~/.aws
nano ~/.aws/credentials
# (or use vim, code, etc.)
```

Add the following block at the end of the file. **Replace the placeholder values** with your own account details:

```ini
[<YOUR_PROFILE_NAME>cont]
credential_process=ada credentials print --account <YOUR_AWS_ACCOUNT_ID> --provider conduit --role <YOUR_ROLE_NAME> --profile=<YOUR_PROFILE_NAME>
```

**Example** (based on the reference setup):
```ini
[spasciencecont]
credential_process=ada credentials print --account 745184793497 --provider conduit --role IibsAdminAccess-DO-NOT-DELETE --profile=spascience
```

**Explanation of the fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `[<YOUR_PROFILE_NAME>cont]` | The profile name you'll use with Goose. The `cont` suffix is a convention to indicate it uses `credential_process` (continuous/auto-refreshing). | `[spasciencecont]` |
| `--account` | Your AWS account ID that has Bedrock access | `745184793497` |
| `--provider` | The identity provider | `conduit` |
| `--role` | The IAM role to assume | `IibsAdminAccess-DO-NOT-DELETE` |
| `--profile` | The ADA profile name (used by `ada` for caching) | `spascience` |

### Step 4.2 — Configure the AWS region for your ADA profile

Open (or create) the file `~/.aws/config`:

```bash
nano ~/.aws/config
```

Add a section for your ADA profile (the one referenced by `--profile` above):

```ini
[<YOUR_PROFILE_NAME>]
region = us-east-1
```

**Example:**
```ini
[spascience]
region = us-east-1
```

> **Note:** The `[spascience]` section in `~/.aws/config` corresponds to the `--profile=spascience` used in the `credential_process` command. The `[spasciencecont]` profile in `~/.aws/credentials` is the one you'll actually export as `AWS_PROFILE`.

---

## 5. Start an Ongoing ADA Credential Refresh Job

ADA credentials expire periodically. To keep them fresh in the background, run an ongoing ADA credential update job as a background process.

### Step 5.1 — Run the background ADA refresh job

```bash
$(ada credentials update --account <YOUR_AWS_ACCOUNT_ID> --provider conduit --role <YOUR_ROLE_NAME> --profile=<YOUR_PROFILE_NAME>) &
```

**Example:**
```bash
$(ada credentials update --account 745184793497 --provider conduit --role IibsAdminAccess-DO-NOT-DELETE --profile=spascience) &
```

This will:
- Prompt you for Midway authentication if needed
- Start caching/refreshing credentials in the background for the `spascience` profile
- The `credential_process` in your `[spasciencecont]` credentials profile will then use these cached credentials via `ada credentials print`

### Step 5.2 — Verify the job is running

```bash
jobs
```

You should see the background ADA job listed.

> **Tip:** If you close your terminal, you will need to re-run this command. Consider adding it to a startup script or running it in a `tmux`/`screen` session for persistence.

---

## 6. Export AWS Environment Variables

Before using Goose or testing Bedrock access, export the following environment variables in your terminal session:

```bash
export AWS_PROFILE=<YOUR_PROFILE_NAME>cont
export AWS_REGION=us-west-1
```

**Example:**
```bash
export AWS_PROFILE=spasciencecont
export AWS_REGION=us-west-1
```

### Verify the variables are set:

```bash
echo "AWS_PROFILE=$AWS_PROFILE"
echo "AWS_REGION=$AWS_REGION"
```

Expected output:
```
AWS_PROFILE=spasciencecont
AWS_REGION=us-west-1
```

> **Important:** These variables must be exported in every new terminal session. To make them persistent, add the export lines to your `~/.bashrc` (or `~/.zshrc`):
> ```bash
> echo 'export AWS_PROFILE=<YOUR_PROFILE_NAME>cont' >> ~/.bashrc
> echo 'export AWS_REGION=us-west-1' >> ~/.bashrc
> ```

---

## 7. Verify Bedrock Access

Before configuring Goose, confirm that your AWS credentials work and you have access to Bedrock.

```bash
aws bedrock list-foundation-models
```

**Expected:** A JSON response listing available foundation models (it can be quite long). You should see models like `anthropic.claude-*` in the output.

**If you get an error:**
- `ExpiredTokenException` → Re-run the ADA credential update from [Step 5](#5-start-an-ongoing-ada-credential-refresh-job)
- `AccessDeniedException` → Your IAM role may not have Bedrock permissions; contact your account admin
- `Could not connect` → Check your `AWS_REGION` and network connectivity

You can also run a filtered check:
```bash
aws bedrock list-foundation-models --query "modelSummaries[?contains(modelId, 'claude')]" --output table
```

---

## 8. Configure Goose

Now we will set up the Goose configuration file. Goose stores its configuration in the directory pointed to by `$XDG_CONFIG_HOME/goose/`. If `XDG_CONFIG_HOME` is not set, it defaults to `~/.config/goose/`.

### Step 8.1 — Determine your config directory

```bash
echo "${XDG_CONFIG_HOME:-$HOME/.config}/goose/"
```

Note the output — this is where your `config.yaml` will live.

### Step 8.2 — Create the configuration directory

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/goose/"
```

### Step 8.3 — Create the Goose configuration file

Create the file `config.yaml` in your Goose config directory:

```bash
cat > "${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml" << 'GOOSE_CONFIG'
AWS_PROFILE: <YOUR_PROFILE_NAME>cont
AWS_REGION: us-east-1
GOOSE_PROVIDER: aws_bedrock
GOOSE_MODEL: us.anthropic.claude-opus-4-8-v1
extensions:
  apps:
    enabled: true
    type: platform
    name: apps
    description: Create and manage custom Goose apps through chat. Apps are HTML/CSS/JavaScript and run in sandboxed windows.
    bundled: true
    available_tools: []
  extensionmanager:
    enabled: true
    type: platform
    name: Extension Manager
    description: Enable extension management tools for discovering, enabling, and disabling extensions
    bundled: true
    available_tools: []
  skills:
    enabled: true
    type: platform
    name: skills
    description: Load and use skills from relevant directories
    bundled: true
    available_tools: []
  code_execution:
    enabled: false
    type: platform
    name: code_execution
    description: Execute JavaScript code in a sandboxed environment
    bundled: true
    available_tools: []
  todo:
    enabled: true
    type: platform
    name: todo
    description: Enable a todo list for goose so it can keep track of what it is doing
    bundled: true
    available_tools: []
  chatrecall:
    enabled: false
    type: platform
    name: chatrecall
    description: Search past conversations and load session summaries for contextual memory
    bundled: true
    available_tools: []
  developer:
    enabled: true
    type: builtin
    name: developer
    description: Code editing and shell access
    display_name: Developer Tools
    timeout: 900
    bundled: true
    available_tools: []
  persistentmemory:
    enabled: false
    type: stdio
    name: PersistentMemory
    description: Persistent memory across sessions
    cmd: npx
    args:
    - -y
    - '@modelcontextprotocol/server-memory'
    envs:
      MEMORY_FILE_PATH: <UPDATE_THIS_TO_YOUR_PATH>/.config/mcp-memory/goose.json
    env_keys: []
    timeout: 300
    bundled: null
    available_tools: []
GOOSE_TELEMETRY_ENABLED: false
GOOSE_CONFIG
```

> **⚠️ Important:** Replace `<YOUR_PROFILE_NAME>cont` with your actual profile name (e.g., `spasciencecont`).

> **Note:** The `builder-mcp` extension is **not** included yet — we will add it in [Step 11](#11-configure-builder-mcp-in-goose) after installing builder-mcp.

### Step 8.4 — Create the permission file

This file auto-approves shell commands so Goose doesn't ask for confirmation every time:

```bash
cat > "${XDG_CONFIG_HOME:-$HOME/.config}/goose/permission.yaml" << 'GOOSE_PERM'
user:
  always_allow:
  - developer__shell
  ask_before: []
  never_allow: []
GOOSE_PERM
```

### Step 8.5 — Verify the configuration

```bash
cat "${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml"
cat "${XDG_CONFIG_HOME:-$HOME/.config}/goose/permission.yaml"
```

Ensure the YAML is valid and the profile name matches what you set up in [Step 4](#4-set-up-aws-credentials).

---

## 9. Hello World Test with Goose (Anthropic Model)

Now let's verify that Goose works end-to-end with AWS Bedrock and the Anthropic Claude model.

### Step 9.1 — Make sure environment variables are set

```bash
export AWS_PROFILE=<YOUR_PROFILE_NAME>cont
export AWS_REGION=us-west-1
```

### Step 9.2 — Launch Goose with the Anthropic model

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s -t "Hello! Can you confirm you are working? Please tell me what model you are and what provider you are using."
```

**Expected:** Goose should respond, confirming it is running on the Claude model via AWS Bedrock.

### Step 9.3 — Exit the session

Type `/exit` or press `Ctrl+C` to exit the Goose session.

✅ **If you got a response — congratulations! Goose is working with Bedrock!**

---

## 10. Install Builder-MCP

Builder-MCP is an MCP (Model Context Protocol) server that gives Goose access to Amazon internal resources such as Apollo, Pipelines, Code Reviews, Tickets, On-call, and more.

### Step 10.1 — Ensure Toolbox is available

```bash
toolbox --version
```

If `toolbox` is not found, ensure `~/.toolbox/bin` is in your PATH:

```bash
export PATH="$HOME/.toolbox/bin:$PATH"
```

And add it permanently to your `~/.bashrc`:

```bash
echo 'export PATH="$HOME/.toolbox/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Step 10.2 — Install builder-mcp via Toolbox

```bash
toolbox install builder-mcp
```

This will download and install the `builder-mcp` binary to `~/.toolbox/bin/builder-mcp`.

### Step 10.3 — Verify the installation

```bash
which builder-mcp
builder-mcp --version
```

Expected output (version may vary):
```
/home/<your-alias>/.toolbox/bin/builder-mcp
Package version: 2.16.1
Toolbox version: 1.0.6295.0
```

### Step 10.4 — (Optional) Get more info about builder-mcp

```bash
toolbox info builder-mcp
```

For full documentation, visit: <https://w.amazon.com/bin/view/BuilderTools/GenAIDevX/Amzn-Software-Builder-MCP/>

---

## 11. Configure Builder-MCP in Goose

Now add the `builder-mcp` extension to your Goose configuration.

### Step 11.1 — Edit the Goose config file

Open your config file:

```bash
nano "${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml"
```

### Step 11.2 — Add the builder-mcp extension block

Add the following block **inside the `extensions:` section**, at the same indentation level as the other extensions (e.g., after the `developer:` block):

```yaml
  builder-mcp:
    enabled: true
    type: stdio
    name: builder-mcp
    description: Amazons builder-mcp
    cmd: builder-mcp
    args: []
    envs: {}
    env_keys: []
    timeout: 300
    bundled: null
    available_tools: []
```

### Step 11.3 — Verify the complete config

After editing, your `extensions:` section should include `builder-mcp`. Verify:

```bash
grep -A 3 "builder-mcp" "${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml"
```

Expected output should show the `builder-mcp` block.

---

## 12. Hello World Test with Builder-MCP

Let's test that builder-mcp is working by asking Goose to look up information about an Amazon employee.

### Step 12.1 — Ensure environment variables are set

```bash
export AWS_PROFILE=<YOUR_PROFILE_NAME>cont
export AWS_REGION=us-west-1
```

### Step 12.2 — Start a new Goose session

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s -t "Please look up the phonetool information for user \"jeff\" using the ReadInternalWebsites tool. Show me their name, job title, and manager."
```

**Expected:** Goose should use the `builder-mcp` extension's `ReadInternalWebsites` tool to fetch information from `phonetool.amazon.com/users/jeff` and display the user's name, job title, and manager information.

> **Note:** You can replace `"jeff"` with any valid Amazon user alias you'd like to look up.

### Step 12.4 — Verify tool usage

Goose should show that it's using the `builder-mcp__ReadInternalWebsites` tool. If you see tool calls being made and results returned, builder-mcp is working correctly!

### Step 12.5 — Exit the session

Type `/exit` or press `Ctrl+C` to exit.

✅ **If you got employee information back — builder-mcp is fully configured and working!**

---

## 13. Troubleshooting

### Goose command not found
```bash
# Check where goose is installed
ls -la ~/.local/bin/goose
# Ensure PATH is correct
echo $PATH | tr ':' '\n' | grep '.local/bin'
# Re-add to PATH if needed
export PATH="$HOME/.local/bin:$PATH"
```

### builder-mcp command not found
```bash
# Check where builder-mcp is installed
ls -la ~/.toolbox/bin/builder-mcp
# Ensure toolbox bin is in PATH
export PATH="$HOME/.toolbox/bin:$PATH"
# Reinstall if needed
toolbox install builder-mcp --force
```

### AWS credentials errors
```bash
# Check current identity
aws sts get-caller-identity

# Re-run ADA credential update
$(ada credentials update --account <YOUR_AWS_ACCOUNT_ID> --provider conduit --role <YOUR_ROLE_NAME> --profile=<YOUR_PROFILE_NAME>) &

# Verify environment variables
echo "AWS_PROFILE=$AWS_PROFILE"
echo "AWS_REGION=$AWS_REGION"
```

### Bedrock access denied
- Ensure your IAM role has `bedrock:*` permissions (or at least `bedrock:InvokeModel`)
- Verify the region supports the model you're trying to use
- Check if the model requires opt-in via the AWS Console (Bedrock → Model access)

### Goose configuration not loading
```bash
# Check where goose is looking for config
echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-not set (defaults to ~/.config)}"
ls -la "${XDG_CONFIG_HOME:-$HOME/.config}/goose/"

# Validate YAML syntax (if python is available)
python3 -c "import yaml; yaml.safe_load(open('${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml'))" && echo "YAML is valid" || echo "YAML has errors"
```

### Goose session hangs or doesn't respond
- Check that your ADA background job is still running: `jobs`
- Try refreshing credentials: re-run the ADA update command from [Step 5](#5-start-an-ongoing-ada-credential-refresh-job)
- Check Bedrock availability in your region

### builder-mcp tools not showing up in Goose
- Ensure `builder-mcp` is set to `enabled: true` in your `config.yaml`
- Ensure the `cmd: builder-mcp` path is correct (i.e., `builder-mcp` is in your PATH)
- Restart the Goose session after making config changes

---

## Quick Reference — Commands Cheat Sheet

```bash
# ---- One-time setup ----
# Install goose
curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | console=yes sh

# Add goose to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Install builder-mcp
toolbox install builder-mcp

# Add toolbox to PATH (if not already)
echo 'export PATH="$HOME/.toolbox/bin:$PATH"' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# ---- Every session ----
# Start ADA credential refresh (background)
$(ada credentials update --account <YOUR_AWS_ACCOUNT_ID> --provider conduit --role <YOUR_ROLE_NAME> --profile=<YOUR_PROFILE_NAME>) &

# Export environment
export AWS_PROFILE=<YOUR_PROFILE_NAME>cont
export AWS_REGION=us-west-1

# Start goose
goose run --model us.anthropic.claude-opus-4-8-v1 -s -t "<initialRequest>"
```

---

> **Questions or issues?** Reach out to the GenAI DevX team at `genai-devx-appdev@amazon.com` for builder-mcp help, or check the [Goose GitHub repository](https://github.com/block/goose) for general Goose issues.
