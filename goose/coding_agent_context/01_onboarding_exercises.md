# 🪿 Goose Onboarding Exercises — Hands-On Guide

> **Prerequisite:** Complete the [Goose Setup Guide](./00_goose_setup_guide.md) first.
> Make sure `goose`, `builder-mcp`, and your AWS/ADA credentials are all working before proceeding.
> Clone this package and checkout the branch `dev_clean_agent` (e.g. `git clone ssh://git.amazon.com/pkg/DlSherpa_tm && cd ./DlSherpa_tm && git checkout -b dev_clean_agent origin/dev_clean_agent`)
>
> **Estimated time:** 2–3 hours (exercises run in parallel where noted)
>
> **Working directory:** All commands assume you are in the **root of your project** — the directory that contains both `coding_agent_context/` and `admin_agent_context/`.

---

## Table of Contents

1. [Overview & Learning Goals](#1-overview--learning-goals)
2. [Pre-Flight Checklist](#2-pre-flight-checklist)
3. [Exercise 1 — Data Exploration Mission (Terminal 1)](#3-exercise-1--data-exploration-mission-terminal-1)
4. [Exercise 2 — Reference Compilation Mission (Terminal 2)](#4-exercise-2--reference-compilation-mission-terminal-2)
5. [Exercise 3 — Generate a Research Report from Compiled References](#5-exercise-3--generate-a-research-report-from-compiled-references)
6. [Exercise 4 — Design Your Own Workflow with Goose](#6-exercise-4--design-your-own-workflow-with-goose)
7. [⭐ Bonus — Drop Into Any Codebase: Generate Docs → Design → Implement](#7--bonus--drop-into-any-codebase-generate-docs--design--implement)
8. [Recap & What You Learned](#8-recap--what-you-learned)

---

## 1. Overview & Learning Goals

These exercises walk you through the core patterns of working with Goose recipes and missions. By the end you will be able to:

| # | Exercise | You will learn… |
|---|----------|-----------------|
| 1 | Data Exploration | How to launch a **coding-agent** mission with a `FEATURE` variable and a recipe |
| 2 | Reference Compilation | How to run an **admin-agent** mission in a **separate terminal** (parallel work) |
| 3 | Research Report | How to **chain missions** — using the output of one as the input to the next |
| 4 | Workflow Generation | How to **design a brand-new workflow** interactively with Goose |

> **Key concept — the `FEATURE` variable pattern:**
> Many recipes are parameterized. The best practice is to **export a shell variable** (e.g. `FEATURE`) and pass it into the `goose run` command via `--params`. This keeps your commands clean and makes them easy to re-run or script.

> [!TIP]
> **⏳ These exercises involve long-running agent executions — that's the point!**
>
> Once you launch a mission, Goose will work autonomously for extended periods (sometimes 30–60+ minutes) without needing your input. **This is by design** — the value of an AI coding agent is that it works while you do other things.
>
> **Use the waiting time productively:**
> - **📺 Watch the stdout** — Follow the real-time output in your terminal. You'll see exactly what the agent is doing step by step: which files it reads, what tools it calls, how it reasons about problems. This is the best way to build intuition for how Goose operates.
> - **📂 Explore the `*_agent_context` directories** — While a mission runs, open a separate terminal and browse through `coding_agent_context/` and `admin_agent_context/`. Read the missions, recipes, roles, specs, and tools files. Understanding the structure will help you design your own workflows later (Exercise 4).
> - **🔀 Run exercises in parallel** — Several exercises are designed to run simultaneously in different terminals. The guide will tell you when.
>
> Think of it like watching a colleague work — you learn patterns, spot conventions, and get ideas just by observing.
>
> For the same reason, it will be beneficial to run this exercise in a screen or tmux session.

---

## 2. Pre-Flight Checklist

Before starting the exercises, run through this quick checklist in your terminal.

```bash
# 1. Verify goose is available
goose --version

# 2. Verify builder-mcp is available
which builder-mcp

# 3. Ensure ADA credentials are refreshing (start if not already running)
#    Replace the placeholders with YOUR values from the setup guide.
$(ada credentials update \
    --account <YOUR_AWS_ACCOUNT_ID> \
    --provider conduit \
    --role <YOUR_ROLE_NAME> \
    --profile=<YOUR_PROFILE_NAME>) &

# 4. Export AWS environment
export AWS_PROFILE=<YOUR_PROFILE_NAME>
export AWS_REGION=us-west-1

# 5. Navigate to your project root
#    This is the directory that contains coding_agent_context/ and admin_agent_context/
cd /path/to/your/project/root

# 6. Verify directory structure
ls coding_agent_context/recipes/
ls admin_agent_context/recipes/
```

✅ If both `ls` commands show `.yaml` recipe files, you are ready to go!

---

## 3. Exercise 1 — Data Exploration Mission (Terminal 1)

### Goal

Launch the **data exploration** mission from `coding_agent_context`. This mission reads an exploration brief, sets up a Docker-based analysis environment, and iteratively explores a dataset. You will use the **`FEATURE` variable pattern** to tell the recipe which exploration spec to use.

### Background

The exploration brief is already prepared at:

```
coding_agent_context/specs/data_exploration_initial_exploartion/exploration.md
```

It describes:
- **Data sources** — two CSV files on S3 (training data and test data)
- **Environment** — AWS profile and region for S3 access
- **Initial questions** — structure, feature types, distributions
- **Docker preferences** — extra pip packages, no GPU required

The recipe file `coding_agent_context/recipes/mission_data_exploration.yaml` will:
1. Read the conventions and mission instructions
2. Set up Docker for reproducible data processing
3. Run the initial exploration iteration
4. Present findings and enter an interactive loop for follow-up analysis

### Step-by-Step

#### Step 1.1 — Open Terminal 1

Open a fresh terminal (or use your current one). Make sure you are in the project root directory.

```bash
cd /path/to/your/project/root
```

#### Step 1.2 — Export your environment

```bash
# AWS credentials (if not already exported)
export AWS_PROFILE=<YOUR_PROFILE_NAME>
export AWS_REGION=us-west-1
```

#### Step 1.3 — Set the FEATURE variable

The `FEATURE` variable tells the recipe which exploration spec folder to use. The folder name pattern is `data_exploration_<FEATURE>`, so we set `FEATURE` to match the existing spec:

```bash
export FEATURE="initial_exploartion"
```

> ⚠️ **Note:** The folder name has a typo (`exploartion` instead of `exploration`). Use the name **exactly as it appears** in the filesystem — the recipe uses this string to locate the spec folder.

#### Step 1.4 — Verify the spec file exists

```bash
cat coding_agent_context/specs/data_exploration_${FEATURE}/exploration.md
```

You should see the exploration brief with data sources, environment settings, and initial questions.

#### Step 1.5 — Launch the mission

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe coding_agent_context/recipes/mission_data_exploration.yaml \
    --params exploration_name="${FEATURE}"
```

#### What happens next

Goose will:
1. Read `coding_agent_context/CONVENTIONS.md` for project rules
2. Read `coding_agent_context/missions/data_exploration.md` for step-by-step instructions
3. Read your exploration brief from `coding_agent_context/specs/data_exploration_${FEATURE}/exploration.md`
4. Set up Docker, run the initial exploration, and present findings
5. Enter an **interactive loop** — it will suggest 3–5 next analysis directions and wait for your input

> 💡 **Tip:** This mission is long-running and interactive. While it is working on Phase 1 (initial exploration), move on to **Exercise 2** in a separate terminal!
>
> 📺 **While you wait:** Keep this terminal visible and follow the stdout — watch how Goose reads the spec, sets up Docker, writes analysis scripts, and interprets results. This is a great opportunity to see an agent's reasoning in real time. In another terminal, start exploring the file structure under `coding_agent_context/` and `admin_agent_context/` — look at missions, recipes, roles, and tools to understand how they fit together.

#### How to interact with the exploration loop

Once the initial exploration completes, Goose will suggest follow-up directions. You can:
- **Select a suggestion** — type the number or describe which direction you want
- **Give a custom direction** — e.g., *"Investigate the correlation between feature X and Y"*
- **Stop** — type `stop` or `exit` to end the mission

---

## 4. Exercise 2 — Reference Compilation Mission (Terminal 2)

### Goal

While Exercise 1 runs in Terminal 1, open a **second terminal** and launch the **reference compilation** mission from `admin_agent_context`. This demonstrates how you can run multiple Goose missions in parallel.

### Background

The reference compilation mission searches internal and external sources for references on a given topic. A requirements file is already prepared for the topic **"Transformer architecture"** at:

```
admin_agent_context/specs/research/20260226_transformer_architecture/requirements.md
```

It specifies:
- **Topic** — Transformer architecture in machine learning
- **Search topics** — "Transformer", "Attention is all you need", "Conformer"
- **Domains** — Internal Amazon sources + arxiv.org
- **Seed source** — The original "Attention Is All You Need" paper
- **Max references** — 20

### Step-by-Step

#### Step 2.1 — Open Terminal 2

Open a **new, separate terminal**. Keep Terminal 1 running with Exercise 1.

```bash
cd /path/to/your/project/root
```

#### Step 2.2 — Export your environment

```bash
# AWS credentials
export AWS_PROFILE=<YOUR_PROFILE_NAME>
export AWS_REGION=us-west-1

# ADA refresh (if not already running in this terminal's session)
$(ada credentials update \
    --account <YOUR_AWS_ACCOUNT_ID> \
    --provider conduit \
    --role <YOUR_ROLE_NAME> \
    --profile=<YOUR_PROFILE_NAME>) &
```

#### Step 2.3 — Set the RUN_DIR variable

The compile-references recipe uses a `run_dir` parameter to know where the requirements file lives and where to write outputs.

```bash
export RUN_DIR="./admin_agent_context/specs/research/20260226_transformer_architecture"
```

#### Step 2.4 — Verify the requirements file

```bash
cat ${RUN_DIR}/requirements.md
```

You should see the YAML-formatted requirements with topic, search_topics, search_domains, and seed_sources.

#### Step 2.5 — Launch the reference compilation mission

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe ./admin_agent_context/recipes/mission_compile_references.yaml \
    --params run_dir="${RUN_DIR}"
```

#### What happens next

Goose will:
1. Read the requirements file
2. Search **internal sources** (wiki, Builder Hub, Sage, code search)
3. Fetch and expand the **seed source** (the original Transformer paper)
4. Search **external sources** (arxiv.org)
5. Score, rank, and deduplicate references
6. Generate two output files:
   - **`compiled_references.md`** — The scored and ranked reference list
   - **`requirements_template.md`** — A pre-filled template for the research report mission (Exercise 3)

#### When it completes

The mission will finish automatically once all searches are done and outputs are written. You will see the final output files at:

```
admin_agent_context/specs/research/20260226_transformer_architecture/
├── requirements.md              # Your original input (unchanged)
├── compiled_references.md       # ✅ NEW — scored reference list
├── requirements_template.md     # ✅ NEW — template for research report
└── progress/
    └── compiler_state.md        # Status tracking
```

> ⏳ **Wait for this to finish before starting Exercise 3.** Exercise 3 depends on the outputs from this step.
>
> 📺 **While you wait — observe and explore!** This is another long-running autonomous execution. Follow the stdout to see how Goose searches internal wikis, fetches papers, scores references, and deduplicates results. You'll notice it working through each search domain methodically — this is a great window into how an agent breaks down a research task.
>
> Meanwhile, familiarize yourself with the mission files, folder structure, roles, etc.
> A great way to do this is to **use Goose itself** to explore the setup interactively. Open a new terminal and run:
>
> ```bash
> goose run --model us.anthropic.claude-opus-4-8-v1 -s -t \
> "In ./coding_agent_context you can find my current agent setup \
> It is meant as a setup that can be dropped into any code package and helps with analysis and development \
> In ./admin_agent_context you find a setup that follows a similar mechanism but geared towards administrative tasks instead of coding \
> Please do an in depth analysis for you to familiarize yourself with those setups. \
> Give me a high level description of what this setup does and how to use it \
> Remember that you can not read more than 5 files at once with the text viewer. \
> Therefore prioritize the use of the shell command cat to read files."
> ```
>
> This will give you a guided tour of the entire agent setup — how missions, recipes, roles, tools, and specs fit together — explained by Goose after it has read through everything.

---

## 5. Exercise 3 — Generate a Research Report from Compiled References

### Goal

Chain two missions together: use the **output** of the reference compilation (Exercise 2) to **generate a full research report**. You will:
1. Use Goose to automatically create a proper `requirements.md` for the research report mission from the compiled references
2. Kick off the research report generation

This exercise teaches the powerful pattern of **mission chaining** — where one mission's output becomes the next mission's input.

### Prerequisites

✅ Exercise 2 must be **complete**. Verify by checking:

```bash
cat ${RUN_DIR}/compiled_references.md | head -20
cat ${RUN_DIR}/requirements_template.md | head -20
```

Both files should exist and contain content.

### Step-by-Step

#### Step 3.1 — Generate a research report requirements file from the compiled references

The compile-references mission produced a `requirements_template.md` file. This is a starting point, but it needs to be finalized into a proper `requirements.md` for the research report mission. We will use Goose to do this automatically.

Run the following command (still in Terminal 2 from the project root):

```bash
export RUN_DIR="./admin_agent_context/specs/research/20260226_transformer_architecture"

goose run --model us.anthropic.claude-opus-4-8-v1 -s -t "
I need you to create a research report requirements file. \
 \
Read the following files for context: \
1. ${RUN_DIR}/requirements.md — the original research topic requirements \
2. ${RUN_DIR}/compiled_references.md — the compiled and scored references \
3. ${RUN_DIR}/requirements_template.md — the template generated by the compile step \
 \
Now create a proper requirements.md for the research_report mission. \
Save it to: ${RUN_DIR}/report_requirements.md \
 \
The file should follow the research report requirements format: \
- topic: 'Transformer architecture' \
- audience.primary: technical_ic \
- report_length_pages: 8 \
- Include ALL sources from compiled_references.md in the sources list \
- Add a storyline that covers: original transformer concept, evolution, modern best practices \
- deep_dive_topics should include: \
  - 'Self-attention mechanism explained simply' \
  - 'Modern training best practices' \
  - 'State-of-the-art transformer variants' \
  - 'Practical design considerations for custom problems' \
- structure: \
  - 'Executive Summary' \
  - 'The Original Transformer — Attention Is All You Need' \
  - 'Evolution of the Architecture' \
  - 'Modern Best Practices in Training' \
  - 'State-of-the-Art Variants' \
  - 'Designing Transformers for Custom Problems' \
  - 'References' \
- Set max_reference_depth: 2 \
- Set max_total_sources: 40 \
- Set default_max_sub_refs: 5 \
- Set min_first_pass_sources: 15 \
"
```

#### Step 3.2 — Verify the generated requirements file

```bash
cat ${RUN_DIR}/report_requirements.md
```

Review the file. It should be a well-structured YAML document with all the sources from the compiled references included.

#### Step 3.3 — Rename the file to be the mission input

The research report recipe expects a file called `requirements.md` in the run directory. Since we already have the original `requirements.md` (for compile-references), we will use a dedicated report directory:

```bash
# Create a dedicated report run directory
export REPORT_RUN_DIR="${RUN_DIR}_report_run"
mkdir -p "${REPORT_RUN_DIR}"

# Copy the generated requirements file as the mission input
cp "${RUN_DIR}/report_requirements.md" "${REPORT_RUN_DIR}/requirements.md"
```

#### Step 3.4 — Launch the research report mission

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe ./admin_agent_context/recipes/mission_research_report.yaml \
    --params run_dir="${REPORT_RUN_DIR}"
```

#### What happens next

The research report mission is the most comprehensive mission in the admin-agent context. Goose will:

1. **Phase 1 — Initialization:** Parse the requirements and set up progress tracking
2. **Phase 2 — First-Pass Investigation:** Skim each source to extract key information
3. **Phase 3 — Relevance Evaluation:** Score sources and decide which ones get a deep dive
4. **Phase 4 — Deep-Dive Investigation:** Thoroughly analyze the most relevant sources
5. **Phase 5 — Report Generation:** Write the final research report with proper citations

The final output will be at:

```
${REPORT_RUN_DIR}/report/final_report.md
```

> ⏳ This mission can take a while (30–60+ minutes depending on source count). It checkpoints its progress, so if interrupted, it can resume. If you want you can skip to Exercise 4 while you wait.
>
> 📺 **While you wait — this is the longest autonomous run in the exercises.** Follow the stdout to watch Goose work through each phase: skimming sources, scoring relevance, performing deep dives, and finally assembling the report. Pay attention to how it tracks progress and handles edge cases (e.g., sources that are unavailable). If you haven't already, use this time to dig into the `*_agent_context` directories — by now you'll recognize the patterns and appreciate how the pieces connect.

#### Step 3.5 — Review the final report

```bash
cat ${REPORT_RUN_DIR}/report/final_report.md
```

You should see a well-structured research report on Transformer architecture with:
- Science-style numbered citations `[1]`, `[2]`, etc.
- Content tailored to a `technical_ic` audience
- A complete reference list at the end

---

## 6. Exercise 4 — Design Your Own Workflow with Goose

### Goal

Use Goose in **interactive mode** to collaboratively design and implement a brand-new workflow. This is the most open-ended exercise — you will experience how Goose can help you **think through, design, and build** a complete workflow from scratch.

### Background

One of the most powerful uses of Goose is as a **design partner**. Instead of just executing predefined missions, you can have an iterative conversation where Goose:
1. Analyzes your existing setup to understand the patterns
2. Proposes a design for a new workflow
3. Iterates on the design based on your feedback
4. Implements it when you are satisfied

Below is an **example trigger command** that demonstrates this pattern. It asks Goose to create a **presentation generation workflow** for the admin-agent context. You can use this as inspiration, modify it, or come up with something completely different.

### Example: Presentation Generation Workflow

This example creates a two-phase workflow:
- **Phase 1 (Story Development):** Create a markdown storyline document with slide content and speaker notes
- **Phase 2 (Slide Generation):** Convert the storyline into LaTeX slides, compiled via Docker

#### Step 4.1 — Study the example trigger

Read through this example trigger command to understand the pattern:

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s -t \
"In ./coding_agent_context you can find my current agent setup \
It is meant as a setup that can be dropped into any code package and helps with analysis and development \
In ./admin_agent_context you find a setup that follows a similar mechanism but geared towards administrative tasks instead of coding \
Please do an in depth analysis for you to familiarize yourself with those setups. \
I then want to add a new workflow to the ./admin_agent_context \
Please develop this workflow with me iteratively until I explicity tell you to implement it. \
I want a workflow to create a presentation. \
That workflow should be split into two phases. The first phase is the development phase that should be a separate mission. \
In that phase the goal is to create a markdown file. Each future slide should be a separate section in this markdown file. \
The section should contain the content of the slide and also a detailed description of the content that should be communicated while showing that slide. \
Then the second phase should be the slide generation phase. \
Once the story line markdown file is generated, it should become the input to a slide generation mission. \
That mission should take some information about the slide style and the story line and then create latex code for the slides. \
It should then kick off a docker based environment in which the latex code is compiled into slides. \
So there is a need for a docker environment for slide generation and a tool that builds an image and runs a container. \
There should be a selection of base slide styles, to select from that should also be part of this package and extendable. \
But there should also be the capability to provide an example slide deck and then to replicate that design for the new slide deck. \
Please now design the mission, role and tool changes to the ./admin_agent_context and then go into an iterative development cycle with me for those new components. \
Then once I explicitly tell you to implement those new components."
```

#### Step 4.2 — Understand the trigger pattern

Notice the key elements of the trigger:

| Element | Purpose |
|---------|---------|
| `goose run --model ... -s -t "..."` | Launch Goose with a specific model, streaming, and a text prompt |
| *"Please do an in depth analysis..."* | First ask Goose to understand the existing setup |
| *"develop this workflow with me iteratively"* | Set the expectation of collaborative iteration |
| *"until I explicitly tell you to implement it"* | Separate design from implementation — you control when code gets written |
| Detailed description of desired workflow | Give Goose enough context to propose a solid initial design |

#### Step 4.3 — Create your own workflow

Now it is your turn! Think of a workflow you would find useful and design it with Goose. Here are some ideas to get you started:

| Idea | Description |
|------|-------------|
| **Meeting Notes Processor** | A workflow that takes raw meeting notes and produces structured summaries, action items, and follow-up tickets |
| **Code Review Assistant** | A multi-phase workflow: first analyze a CR for issues, then generate review comments, then track resolution |
| **Onboarding Document Generator** | Take a team wiki and generate personalized onboarding checklists for new hires |
| **Incident Post-Mortem Builder** | Collect ticket data, logs, and timeline info to draft a COE/post-mortem document |

#### Step 4.4 — Launch your design session

Craft your trigger command following this template:

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s -t \
"In ./coding_agent_context you can find my current coding agent setup. \
In ./admin_agent_context you find a similar setup geared towards administrative tasks. \
Please analyze both setups to understand the patterns and conventions used. \
\
I want to add a new workflow to the ./admin_agent_context (or ./coding_agent_context). \
Please develop this workflow with me iteratively until I explicitly tell you to implement it. \
\
<DESCRIBE YOUR WORKFLOW HERE> \
\
Please design the mission, role, and tool changes needed and then go into an iterative \
development cycle with me for those new components."
```

#### Tips for a productive design session

- **Be specific about the end goal** — What file(s) should be produced? What format?
- **Describe the phases** — Most good workflows have distinct stages (research → design → implement → verify)
- **Mention constraints** — Docker required? Specific tools? Output formats?
- **Iterate!** — Don't try to get it perfect in one shot. Give feedback, ask for changes, refine.
- **Say "implement" only when ready** — Goose will wait for your explicit go-ahead before writing files

---

## 7. ⭐ Bonus — Drop Into Any Codebase: Generate Docs → Design → Implement

> **This exercise is optional.** It shows you how to take the `coding_agent_context` you've been exploring throughout these exercises and use it in **your own real code package** — moving from onboarding into actual day-to-day agent-assisted development.

### The Big Idea

The `coding_agent_context/` directory is designed to be **portable**. You can copy it into any code repository and immediately have a full suite of agent-powered workflows available — documentation generation, architectural design, TDD implementation, data exploration, code review, and more.

The recommended first step after dropping it in is always the same: **generate documentation**.

### Why Document Generation First?

When you point Goose at an unfamiliar codebase, it faces the same challenge any new developer does — it needs to understand the code before it can contribute effectively. The **generate docs** mission (`mission_generate_docs.yaml`) solves this problem in a powerful way:

1. **It forces a full codebase scan.** The mission systematically walks through every directory, module, and component — nothing is missed.
2. **It produces compressed, structured references.** The output is a set of `*_Agent.md` files plus an `INDEX_Agent.md` — each one a concise summary of a logical component (its purpose, key classes/functions, dependencies, and interactions).
3. **These docs become the agent's memory.** In subsequent missions (design, TDD, exploration), Goose reads these generated docs first. Instead of re-scanning thousands of source files each time, it loads a compact, pre-digested map of the entire system. This dramatically improves the quality and speed of all follow-up work.
4. **You benefit too.** The generated docs serve as genuine onboarding material for human developers as well — accurate, up-to-date, and comprehensive.

> 💡 **Think of it this way:** Generating docs is like having a new team member spend their first week reading and summarizing every part of the codebase — except it takes 30–60 minutes and the summaries are always current.

### Step-by-Step: Drop In and Generate Docs

#### Step 7.1 — Copy `coding_agent_context/` into your target package

Navigate to your target code repository and copy the entire context directory:

```bash
cd /path/to/your/code/package

# Copy the coding_agent_context from where you set it up during onboarding
cp -r /path/to/onboarding/project/coding_agent_context ./coding_agent_context
```

Make sure that you either copy the 'clean' `coding_agent_context` or you delete the content of `coding_agent_context/specs` after copying.

> 📁 Your repository should now look like:
> ```
> your-code-package/
> ├── coding_agent_context/    ← Newly added
> │   ├── CONVENTIONS.md
> │   ├── missions/
> │   ├── recipes/
> │   ├── roles/
> │   ├── specs/
> │   └── tools/
> ├── src/                     ← Your existing code
> ├── tests/                   ← Your existing tests
> └── ...
> ```

#### Step 7.2 — Export your environment and run the doc generation mission

```bash
export AWS_PROFILE=<YOUR_PROFILE_NAME>
export AWS_REGION=us-west-1

goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe coding_agent_context/recipes/mission_generate_docs.yaml
```

#### What happens

Goose will:
1. Read `CONVENTIONS.md` and the `generate_docs.md` mission instructions
2. **Phase 1 — Analyze & Plan:** Explore the entire repository structure, analyze major components using its sub-agent tools, and produce a `plan.md` listing every logical component ("Agent") to document
3. **Phase 2 — Execute:** For each component in the plan, perform deep analysis and write a `*_Agent.md` file, then create an `INDEX_Agent.md` that ties everything together

The output lands in `coding_agent_context/docs/`:

```
coding_agent_context/docs/
├── INDEX_Agent.md              ← Start here — overview + architecture diagram
├── DataProcessing_Agent.md     ← One doc per logical component
├── APILayer_Agent.md
├── Authentication_Agent.md
└── ...
```

#### Step 7.3 — Review the generated documentation

```bash
cat coding_agent_context/docs/INDEX_Agent.md
```

This index file gives you (and the agent) a complete map of the codebase: what each component does, how they relate, and where to find details.

---

### What Comes Next: The Design → Implement Workflow

Once documentation is generated, you have a powerful foundation for making changes. The `coding_agent_context` provides two missions that chain together naturally:

#### Phase A — Architectural Design (`mission_architecture_design.yaml`)

Use this mission when you want to **plan a new feature or change** before writing any code. It follows a structured process:

1. You write a `requirements.md` describing what you want to build (placed in `coding_agent_context/specs/<your_feature>/requirements.md`)
2. The agent reads your generated docs to understand the existing architecture and direct further deeper analysis
3. It produces a **design document** (`design.md`) with: component changes, new interfaces, data flow, edge cases, and a step-by-step implementation plan
4. The design includes Docker-awareness — it accounts for the containerized execution environment

```bash
export FEATURE="my_new_feature"
# First, create your requirements:
mkdir -p coding_agent_context/specs/${FEATURE}
# Write your requirements.md describing the feature...

# Then launch the design mission:
goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe coding_agent_context/recipes/mission_architecture_design.yaml \
    --params feature="${FEATURE}"
```

> The design mission deliberately separates **thinking** from **doing**. It produces a plan but writes no production code — giving you a chance to review and refine before any implementation begins.

#### Phase B — TDD Implementation (`mission_tdd.yaml`)

Once you're satisfied with the design, chain directly into the TDD mission. This is where the agent **actually writes code** — but in a disciplined way:

1. It reads the `design.md` produced by Phase A
2. For each step in the implementation plan, it follows strict **Red-Green-Refactor TDD**:
   - 🔴 **Red:** Write a failing test first (via the `qa_engineer` sub-agent)
   - 🟢 **Green:** Write the minimum code to make it pass (via the `developer` sub-agent)
   - 🔄 **Refactor:** Clean up while keeping tests green
3. All code execution happens inside Docker — tests, linting, and scripts never run on your host
4. It maintains a `memory.md` file that carries learnings across sessions (e.g., Docker quirks, dependency notes)

```bash
goose run --model us.anthropic.claude-opus-4-8-v1 -s \
    --recipe coding_agent_context/recipes/mission_tdd.yaml \
    --params feature="${FEATURE}"
```

### The Full Flow at a Glance

```
┌─────────────────────────────────────────────────────────────────────┐
│  1. DROP IN        cp -r coding_agent_context/ into your package   │
│  2. GENERATE DOCS  mission_generate_docs → docs/*_Agent.md         │
│  3. DESIGN         mission_architecture_design → specs/*/design.md │
│  4. IMPLEMENT      mission_tdd → code changes with full test suite │
└─────────────────────────────────────────────────────────────────────┘
```

> 🔑 **Why this order matters:**
> - **Docs first** gives the agent (and you) a compressed map of the entire codebase, so every subsequent mission starts with strong context rather than scanning from scratch.
> - **Design before implementation** catches architectural issues early and produces a reviewable plan.
> - **TDD for implementation** ensures every change is backed by tests from the start — the agent can't "cheat" by writing untested code.

---

## 8. Recap & What You Learned

### Exercise Summary

| Exercise | Context | Pattern | Key Takeaway |
|----------|---------|---------|--------------|
| 1 — Data Exploration | `coding_agent_context` | `export FEATURE=... → goose run --recipe ... --params` | Parameterized recipe execution with the FEATURE variable pattern |
| 2 — Reference Compilation | `admin_agent_context` | Same pattern, separate terminal | Running missions in parallel across different agent contexts |
| 3 — Research Report | `admin_agent_context` | Output of mission 2 → input to mission 3 | Mission chaining — composing workflows from smaller missions |
| 4 — Workflow Generation | Either context | Interactive `goose run -s -t "..."` | Using Goose as an iterative design partner to create new workflows |
| ⭐ Bonus — Drop In & Build | `coding_agent_context` | Generate Docs → Design → TDD | Portable agent context: doc generation as foundation for agent-assisted development |

### The Core Workflow Pattern

Every mission follows the same fundamental pattern:

```
┌────────────────────────────────────────────────────────────────┐
│  1. PREPARE      Export variables, verify requirements file    │
│  2. LAUNCH       goose run --recipe <recipe.yaml> --params    │
│  3. INTERACT     Respond to prompts, guide the mission        │
│  4. REVIEW       Check outputs, chain to next mission         │
└────────────────────────────────────────────────────────────────┘
```

### File Structure Reference

```
project_root/
├── coding_agent_context/
│   ├── 00_goose_setup_guide.md          ← Setup guide
│   ├── 01_onboarding_exercises.md       ← This file (exercises)
│   ├── CONVENTIONS.md                    ← Project conventions
│   ├── missions/                         ← Mission step-by-step instructions
│   │   └── data_exploration.md
│   ├── recipes/                          ← Goose recipe files (YAML)
│   │   └── mission_data_exploration.yaml
│   ├── roles/                            ← Sub-agent role definitions
│   ├── specs/                            ← Mission specifications / inputs
│   │   └── data_exploration_initial_exploartion/
│   │       └── exploration.md
│   └── tools/                            ← Shell tools (Docker, test runners)
│
└── admin_agent_context/
    ├── CONVENTIONS.md
    ├── missions/
    │   ├── compile_references.md
    │   └── research_report.md
    ├── recipes/
    │   ├── mission_compile_references.yaml
    │   └── mission_research_report.yaml
    ├── roles/
    ├── specs/
    │   └── research/
    │       └── 20260226_transformer_architecture/
    │           └── requirements.md
    └── user_guides/                      ← Additional documentation
```

---

## Need Help?

- **Goose not responding?** Check that your ADA credentials are still refreshing (`jobs` to see background processes)
- **Recipe not found?** Make sure you are in the **project root** directory (the one containing `coding_agent_context/`)
- **Model errors?** Verify `AWS_PROFILE` and `AWS_REGION` are exported correctly
- **General issues?** See the [Troubleshooting section](./00_goose_setup_guide.md#13-troubleshooting) in the setup guide

---

> **You've completed the onboarding exercises!** 🎉
> You now know how to run parameterized missions, work in parallel, chain missions together, and design new workflows with Goose.
