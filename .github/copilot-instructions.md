# GitHub Copilot Instructions for chef-powershell-shim

## Repository Overview

This repository contains the **chef-powershell-shim**, a .NET Assembly that facilitates communication between Chef and PowerShell on Windows platforms. It includes both .NET components and a Ruby gem (`chef-powershell`) that provides the interface between Chef and PowerShell via FFI.

## Repository Structure

```
chef-powershell-shim/
├── .github/                           # GitHub workflows and configurations
│   ├── workflows/                     # CI/CD pipelines
│   │   ├── ci-main-pull-request-checks-stub.yml
│   │   ├── gem-build.yml
│   │   ├── manual-gem-build.yml
│   │   └── tester.yml
│   └── dependabot.yml
├── Chef.PowerShell/                   # Main .NET PowerShell assembly
│   ├── Chef.PowerShell.csproj
│   ├── Execution.cs
│   ├── PowerShell.cs
│   └── Properties/
├── Chef.Powershell.Core/              # .NET Core PowerShell assembly
│   ├── Chef.Powershell.Core.csproj
│   ├── Execution.cs
│   └── PowerShell.cs
├── Chef.PowerShell.Wrapper/           # Native C++ wrapper
│   └── [C++ implementation files]
├── Chef.PowerShell.Wrapper.Core/      # Core native wrapper
│   └── [C++ implementation files]
├── chef-powershell/                   # Ruby gem source
│   ├── lib/                          # Main Ruby library code
│   │   ├── chef-powershell.rb        # Main entry point
│   │   └── chef-powershell/          # Core modules
│   │       ├── exceptions.rb
│   │       ├── powershell_exec.rb    # PowerShell execution logic
│   │       ├── powershell.rb         # PowerShell interface
│   │       ├── pwsh.rb              # PowerShell Core interface
│   │       ├── unicode.rb
│   │       ├── version.rb
│   │       └── wide_string.rb
│   ├── spec/                         # RSpec test files
│   │   └── unit/
│   │       └── powershell_exec_spec.rb
│   ├── tasks/                        # Rake tasks
│   ├── Gemfile                       # Ruby dependencies
│   └── chef-powershell.gemspec       # Gem specification
├── habitat/                          # Habitat packaging
└── [Root configuration files]
```

## Key Technologies

- **.NET Framework 4.8.1** and **.NET 8.0**: Core PowerShell assemblies
- **Ruby 3.1+**: chef-powershell gem
- **FFI**: Foreign Function Interface for Ruby-to-.NET communication
- **PowerShell/PowerShell Core**: Target execution environments
- **RSpec**: Testing framework for Ruby components
- **C++**: Native wrapper components

## JIRA Integration Workflow

### When a JIRA ID is provided:

1. **Fetch JIRA Issue Details**: Use the `atlassian-mcp-server` MCP server to retrieve issue information
   ```
   # Use mcp_atlassian-mcp_getJiraIssue to fetch issue details
   # Read the story description, acceptance criteria, and requirements
   ```

2. **Analyze Requirements**: Parse the JIRA issue to understand:
   - Feature requirements
   - Acceptance criteria
   - Implementation scope
   - Testing requirements

3. **Implementation Planning**: Create a detailed plan based on JIRA requirements

## Testing Requirements

- **Minimum Test Coverage**: Maintain >80% code coverage for all implementations
- **Test Types Required**:
  - Unit tests for all new methods and classes
  - Integration tests for PowerShell execution flows
  - Error handling tests for exception scenarios
  - Cross-platform compatibility tests (where applicable)

### Testing Guidelines

- Use **RSpec** for Ruby component testing
- Follow existing test patterns in `chef-powershell/spec/unit/`
- Test both Windows PowerShell (`:powershell`) and PowerShell Core (`:pwsh`) interpreters
- Include edge cases and error conditions
- Mock external dependencies appropriately

## Development Workflow

### Complete Implementation Workflow:

1. **Initial Setup**
   - Fetch and analyze JIRA issue (if provided)
   - Review current codebase
   - Identify files to be modified
   - Plan implementation approach

2. **Implementation Phase**
   - Write code following existing patterns
   - Ensure compatibility with both .NET Framework and .NET Core
   - Handle both PowerShell and PowerShell Core scenarios
   - Follow Ruby and C# coding standards

3. **Testing Phase**
   - Create comprehensive unit tests
   - Ensure >80% test coverage
   - Test error scenarios and edge cases
   - Validate cross-platform compatibility

4. **Quality Assurance**
   - Run all existing tests to ensure no regressions
   - Perform code review checks
   - Validate against JIRA acceptance criteria

5. **Branch and PR Creation**
   - Create branch using JIRA ID as branch name
   - Commit changes with descriptive messages
   - Push to remote repository
   - Create pull request with detailed description

### Branch and PR Management

**When prompted to create a PR:**

1. **Branch Creation**: Use JIRA ID as branch name
   ```bash
   git checkout -b [JIRA_ID]
   git add .
   git commit -m "Implement [JIRA_ID]: [Brief description]"
   git push origin [JIRA_ID]
   ```

2. **PR Creation using GitHub CLI**:
   ```bash
   # Authenticate with GitHub (no ~/.profile references)
   gh auth login
   
   # Create PR
   gh pr create --title "[JIRA_ID]: [Title]" --body "[HTML formatted description]"
   ```

3. **PR Description Format**: Use HTML tags for formatting
   ```html
   <h2>Summary</h2>
   <p>Brief description of changes made</p>
   
   <h2>JIRA Issue</h2>
   <p>Link: [JIRA_URL]</p>
   
   <h2>Changes Made</h2>
   <ul>
     <li>Change 1</li>
     <li>Change 2</li>
   </ul>
   
   <h2>Testing</h2>
   <p>Description of tests added and coverage achieved</p>
   ```

## Prompt-Based Task Execution

### Task Flow Protocol:

1. **After Each Step**: Provide a summary of what was completed
2. **Next Step Preview**: Clearly state what the next step will be
3. **Remaining Steps**: List all remaining steps in the workflow
4. **Continuation Prompt**: Always ask "Do you want to continue with the next step?"

### Example Flow:
```
✅ Step 1 Complete: Fetched JIRA issue [ID] and analyzed requirements
📋 Summary: Understanding requirements for PowerShell execution enhancement

🔄 Next Step: Implement core functionality in chef-powershell/lib/chef-powershell/powershell_exec.rb
📝 Remaining Steps: 
   - Write unit tests
   - Validate test coverage >80%
   - Create branch and PR

❓ Do you want to continue with the next step?
```

## File Modification Guidelines

### Prohibited Modifications:
- Do not modify `.expeditor/` configuration files
- Do not change habitat packaging without explicit requirements
- Avoid modifying core .NET assembly signatures unless required
- Do not alter existing gem specification without version considerations

### Safe to Modify:
- Ruby library files in `chef-powershell/lib/`
- Test files in `chef-powershell/spec/`
- Documentation files
- Build scripts (with caution)

## MCP Server Integration

### Atlassian MCP Server Usage:

When working with JIRA issues, use the `atlassian-mcp-server` MCP server:

1. **Get Accessible Resources**:
   ```
   mcp_atlassian-mcp_getAccessibleAtlassianResources
   ```

2. **Fetch Issue Details**:
   ```
   mcp_atlassian-mcp_getJiraIssue(cloudId, issueIdOrKey)
   ```

3. **Search for Issues**:
   ```
   mcp_atlassian-mcp_search(query)
   ```

4. **Update Issue Status**:
   ```
   mcp_atlassian-mcp_transitionJiraIssue(cloudId, issueIdOrKey, transition)
   ```

## Quality Standards

- **Code Coverage**: Always maintain >80% test coverage
- **Documentation**: Update relevant README files when adding features
- **Compatibility**: Ensure compatibility with both Windows PowerShell and PowerShell Core
- **Error Handling**: Implement comprehensive error handling with appropriate exceptions
- **Performance**: Consider performance implications for PowerShell execution paths

## Git and GitHub Best Practices

- Use descriptive commit messages referencing JIRA IDs
- Create focused, single-purpose branches
- Include comprehensive PR descriptions with HTML formatting
- Link PRs to corresponding JIRA issues

## Communication Protocol

- Always provide step-by-step progress updates
- Request confirmation before proceeding to next major steps
- Clearly communicate what files will be modified
- Explain the reasoning behind implementation decisions
- Report test coverage results after implementation
