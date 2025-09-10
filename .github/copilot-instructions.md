# GitHub Copilot Instructions for chef-powershell-shim

## Repository Overview

The chef-powershell-shim repository contains a .NET Assembly to facilitate communication between Chef and PowerShell on the Windows platform. It includes both .NET components and a Ruby gem (chef-powershell) that provides the interface between Chef and PowerShell via FFI.

## Repository Structure

```
chef-powershell-shim/
├── README.md                          # Main project documentation
├── LICENSE                           # Apache License 2.0
├── VERSION                           # Version information
├── CHANGELOG.md                      # Release notes (Expeditor managed)
├── Rakefile                          # Ruby build tasks
├── Chef.PowerShell.sln              # Visual Studio solution file
├── sonar-project.properties         # SonarQube configuration
├── 
├── .github/                          # GitHub configuration
│   ├── dependabot.yml              # Dependency management
│   └── workflows/                   # CI/CD workflows
│       ├── ci-main-pull-request-checks-stub.yml
│       ├── gem-build.yml
│       ├── manual-gem-build.yml
│       └── tester.yml
│
├── .expeditor/                       # Expeditor build system
│   ├── config.yml                   # Main Expeditor configuration
│   ├── build.habitat.yml
│   ├── build_gems.ps1
│   ├── manual_gem_release.ps1
│   └── update_version.sh
│
├── chef-powershell/                  # Ruby gem source
│   ├── README.md                     # Gem-specific documentation
│   ├── chef-powershell.gemspec      # Gem specification
│   ├── Gemfile                      # Ruby dependencies
│   ├── Rakefile                     # Gem-specific build tasks
│   ├── lib/                         # Ruby library code
│   │   ├── chef-powershell.rb       # Main entry point
│   │   └── chef-powershell/         # Core implementation
│   │       ├── exceptions.rb
│   │       ├── powershell_exec.rb
│   │       ├── powershell.rb
│   │       ├── pwsh.rb
│   │       ├── unicode.rb
│   │       ├── version.rb
│   │       └── wide_string.rb
│   ├── spec/                        # RSpec test suite
│   │   └── unit/
│   │       └── powershell_exec_spec.rb
│   └── tasks/                       # Rake task definitions
│       ├── dependencies.rb
│       ├── rspec.rb
│       └── spellcheck.rb
│
├── Chef.PowerShell/                  # .NET Framework assembly
│   ├── Chef.PowerShell.csproj
│   ├── Execution.cs
│   ├── PowerShell.cs
│   └── Properties/
│       └── AssemblyInfo.cs
│
├── Chef.Powershell.Core/            # .NET Core assembly
│   ├── Chef.Powershell.Core.csproj
│   ├── Execution.cs
│   └── PowerShell.cs
│
├── Chef.PowerShell.Wrapper/         # Native Windows wrapper
│   ├── Chef.PowerShell.Wrapper.vcxproj
│   ├── Chef.PowerShell.Wrapper.cpp
│   ├── Chef.PowerShell.Wrapper.h
│   └── [other C++ source files]
│
├── Chef.PowerShell.Wrapper.Core/    # Core wrapper implementation
│   ├── Chef.PowerShell.Wrapper.Core.vcxproj
│   ├── Chef.PowerShell.Wrapper.Core.cpp
│   └── [other related files]
│
└── habitat/                         # Habitat packaging
    └── plan.ps1                     # Habitat build plan
```

## Development Workflow

### 1. Task Implementation Process

When implementing tasks, follow this comprehensive workflow:

#### Step 1: Jira Integration (when Jira ID provided)
- **ALWAYS** use the MCP Atlassian server to fetch Jira issue details when a Jira ID is provided
- Read the complete story description, acceptance criteria, and requirements
- Understand the scope and context before beginning implementation
- Use the Jira ID as the branch name for version control

#### Step 2: Branch Creation and Setup
```bash
# Create and switch to feature branch using Jira ID
git checkout -b JIRA-123
```

#### Step 3: Implementation
- Implement the required functionality based on Jira requirements
- Follow existing code patterns and conventions
- Ensure compatibility with both Windows PowerShell and PowerShell Core
- Update relevant documentation as needed

#### Step 4: Testing Requirements
- **MANDATORY**: Create comprehensive unit test cases for all new functionality
- Maintain test coverage above 80% at all times
- Use RSpec for Ruby components testing
- Test both .NET Framework and .NET Core implementations where applicable
- Validate PowerShell integration for both Windows PowerShell and PowerShell Core

#### Step 5: Code Quality
- Follow existing code style and conventions
- Ensure all commits are signed with DCO (Developer Certificate of Origin)
- Run all existing tests to ensure no regressions
- Validate SonarQube compliance

#### Step 6: Pull Request Creation
- Use GitHub CLI to create PR with proper formatting
- Include comprehensive summary of changes in HTML format
- Link to related Jira issue
- Apply appropriate GitHub labels

### 2. DCO Compliance Requirements

**ALL commits MUST be signed with DCO (Developer Certificate of Origin):**

```bash
# For each commit, use the -s flag
git commit -s -m "Your commit message"
```

The DCO sign-off certifies that you wrote the code or have the right to submit it. All commits without proper DCO sign-off will be rejected.

### 3. Expeditor Build System Integration

This repository uses Expeditor for automated build and release management:

#### Available Expeditor Labels:
- `Expeditor: Bump Version Major` - Bumps major version number
- `Expeditor: Bump Version Minor` - Bumps minor version number  
- `Expeditor: Skip All` - Skips all merge actions
- `Expeditor: Skip Changelog` - Skips changelog update
- `Expeditor: Skip Habitat` - Skips Habitat package build
- `Expeditor: Skip Omnibus` - Skips Omnibus release build
- `Expeditor: Skip Version Bump` - Skips version bumping

#### Release Branches:
- `main` - Version constraint: 19.*
- `18-Stable` - Version constraint: 18.*

### 4. GitHub Repository Labels

Apply appropriate labels to PRs based on the change type:

#### Code-specific Labels:
- `.NET` - Pull requests that update .NET code
- `dependencies` - Pull requests that update a dependency file

#### Aspect Labels:
- `Aspect: Integration` - Works correctly with other projects or systems
- `Aspect: Packaging` - Distribution of compiled artifacts
- `Aspect: Performance` - Performance-related changes
- `Aspect: Portability` - Platform compatibility changes
- `Aspect: Security` - Security-related modifications
- `Aspect: Stability` - Stability improvements
- `Aspect: Testing` - Test coverage and CI improvements
- `Aspect: UI` - User interface changes
- `Aspect: UX` - User experience improvements

#### Platform Labels:
- `Platform: AWS` - AWS-specific changes
- `Platform: Azure` - Azure-specific changes
- `Platform: Debian-like` - Debian/Ubuntu compatibility
- `Platform: Docker` - Docker-related changes
- `Platform: GCP` - Google Cloud Platform changes
- `Platform: Linux` - Linux-specific changes
- `Platform: macOS` - macOS-specific changes
- `Platform: RHEL-like` - RHEL/CentOS compatibility

#### Special Labels:
- `DO NOT MERGE` - Do not merge this PR
- `documentation` - Documentation updates
- `hacktoberfest-accepted` - Accepted Hacktoberfest contribution
- `oss-standards` - OSS repository standardization

### 5. Pull Request Creation Workflow

When prompted to create a PR, follow this automated process:

```bash
# 1. Ensure all changes are committed with DCO
git add .
git commit -s -m "Implement JIRA-123: [Brief description of changes]"

# 2. Push branch to origin
git push origin JIRA-123

# 3. Create PR using GitHub CLI with formatted description
gh pr create \
  --title "JIRA-123: [Brief title]" \
  --body "$(cat <<EOF
<h2>Summary</h2>
<p>[Detailed summary of changes made]</p>

<h2>Changes</h2>
<ul>
<li>[List of specific changes]</li>
<li>[Additional changes]</li>
</ul>

<h2>Testing</h2>
<ul>
<li>[Testing approach and coverage]</li>
<li>[Test results summary]</li>
</ul>

<h2>Related Issues</h2>
<p>Resolves: JIRA-123</p>
EOF
)" \
  --label "aspect-label,platform-label" \
  --assignee @me
```

### 6. Prompt-Based Development

**All tasks must be performed in a prompt-based manner:**

1. **After each step**, provide a comprehensive summary of what was completed
2. **Before proceeding**, clearly state what the next step will be
3. **List remaining steps** for full transparency
4. **Always ask for confirmation** before proceeding to the next step

Example interaction pattern:
```
✅ Completed: [Step description]
📋 Summary: [What was accomplished]
🔄 Next Step: [What will be done next]
📝 Remaining: [List of remaining steps]
❓ Continue with next step? (y/n)
```

### 7. File Modification Restrictions

**DO NOT modify these files without explicit approval:**
- `.expeditor/config.yml` - Expeditor configuration
- `VERSION` - Version is managed by Expeditor
- `CHANGELOG.md` - Managed by Expeditor
- `.github/workflows/` - CI/CD pipeline files
- `habitat/plan.ps1` - Habitat packaging configuration

### 8. Development Prerequisites and Environment

Ensure the following are installed for local development:
- .NET Framework 4.8.1 development pack
- Windows 11 SDK build 26100
- .NET 8.0.303 or later
- MS Build Tools 17.11.2 or later
- Habitat CLI (for package builds)

Required environment variables:
```powershell
$env:MSBuildEnableWorkloadResolver = "false"
$env:HAB_BLDR_CHANNEL = "base-2025"
$env:MSBuildSdksPath = "C:\Program Files\dotnet\sdk"
$env:HAB_ORIGIN = "chef"
```

### 9. Testing and Quality Assurance

- **Minimum test coverage**: 80%
- Use RSpec for Ruby components
- Test both PowerShell and PowerShell Core integration
- Validate cross-platform compatibility where applicable
- Run SonarQube analysis for code quality

### 10. MCP Server Integration

For Atlassian/Jira integration, use the `atlassian-mcp-server`:
- Fetch issue details using the MCP server tools
- Parse requirements and acceptance criteria
- Link PRs back to Jira issues
- Update issue status as appropriate

This ensures seamless integration between development workflow and project management tools while maintaining high code quality and proper documentation standards.