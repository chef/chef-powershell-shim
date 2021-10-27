# chef-powershell-shim

A .NET Assembly to facilitate communication between Chef and PowerShell on the Windows platform. This repo now also contains the chef-powershell Ruby gem which consumes the the .NET Assembly and provides the interface between Chef and PowerShell via ffi.

### Development Prerequisites

Binaries can be built with Habitat. See the Rake task ```:update_chef_powershell_dlls``` in the chef-powershell/Rakefile

## Contributing/Development

Please read our [Community Contributions Guidelines](https://docs.chef.io/community_contributions.html), and
ensure you are signing all your commits with DCO sign-off.

The general development process is:

1. Fork this repo and clone it to your workstation.
2. Create a feature branch for your change.
3. Write code and tests.
4. Push your feature branch to github and open a pull request against master.

Once your repository is set up, you can start working on the code.  We do utilize
RSpec for test driven development, so you'll need to get a development
environment running. Follow the above procedure ("Installing from Git") to get
your local copy of the source running.

# License

|                      |                                          |
|:---------------------|:-----------------------------------------|
| **Author:**          | Stuart Preston (<stuart@chef.io>)
| **Copyright:**       | Copyright 20, Chef Software, Inc.
| **License:**         | Apache License, Version 2.0

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
