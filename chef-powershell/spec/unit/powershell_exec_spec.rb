#
# Author:: Stuart Preston (<stuart@chef.io>)
# Copyright:: Copyright (c) Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef-powershell"

describe ChefPowerShell::ChefPowerShellModule::PowerShellExec, :windows_only do
  let(:powershell_mixin) { Class.new { include ChefPowerShell::ChefPowerShellModule::PowerShellExec } }
  subject(:object) { powershell_mixin.new }

  before do
    file_path = Gem.loaded_specs["chef-powershell"].full_gem_path + "/bin/ruby_bin_folder/#{ENV["PROCESSOR_ARCHITECTURE"]}/"
    ENV["CHEF_POWERSHELL_BIN"] = file_path
  end

  describe "#powershell_exec" do
    context "not specifying an interpreter" do
      it "runs a basic command and returns a Chef::PowerShell object" do
        expect(object.powershell_exec("$PSVersionTable", :powershell, timeout: -1)).to be_kind_of(ChefPowerShell::PowerShell)
      end

      it "uses less than version 7" do
        execution = object.powershell_exec("$PSVersionTable", :powershell, timeout: -1)
        expect(execution.result["PSVersion"].to_s.to_i).to be < 7
      end
    end

    context "using pwsh interpreter" do
      it "runs a basic command and returns a Chef::PowerShell object" do
        expect(object.powershell_exec("$PSVersionTable", :pwsh, timeout: -1)).to be_kind_of(ChefPowerShell::Pwsh)
      end

      it "uses greater than version 6" do
        execution = object.powershell_exec("$PSVersionTable", :pwsh, timeout: -1)
        expect(execution.result["PSVersion"]["Major"]).to be >= 7
      end
    end

    context "using powershell interpreter" do
      it "runs a basic command and returns a Chef::PowerShell object" do
        expect(object.powershell_exec("$PSVersionTable", :powershell, timeout: -1)).to be_kind_of(ChefPowerShell::PowerShell)
      end

      it "uses less than version 6" do
        execution = object.powershell_exec("$PSVersionTable", :powershell, timeout: -1)
        expect(execution.result["PSVersion"].to_s.to_i).to be < 6
      end
    end

    it "runs a command that fails with a non-terminating error and can trap the error via .error?" do
      execution = object.powershell_exec("this-should-error")
      expect(execution.error?).to eql(true)
    end

    it "runs a command that fails with a non-terminating error and can list the errors" do
      execution = object.powershell_exec("this-should-error")
      expect(execution.errors).to be_a_kind_of(Array)
      expect(execution.errors[0]).to be_a_kind_of(String)
      expect(execution.errors[0]).to include("The term 'this-should-error' is not recognized")
    end

    it "raises an error if the interpreter is invalid" do
      expect { object.powershell_exec("this-should-error", :power_mistake) }.to raise_error(ArgumentError)
    end
  end

  describe "#powershell_exec!" do
    it "runs a basic command and returns a Chef::PowerShell object" do
      expect(object.powershell_exec!("$PSVersionTable", :powershell, timeout: -1)).to be_kind_of(ChefPowerShell::PowerShell)
    end

    it "raises an error if the command fails" do
      expect { object.powershell_exec!("this-should-error") }.to raise_error(ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed)
    end

    it "raises an error if the interpreter is invalid" do
      expect { object.powershell_exec!("this-should-error", :power_mistake) }.to raise_error(ArgumentError)
    end

    let(:cert_script) do
      %q~
        $serverauth = New-SelfSignedCertificate -Subject "chef-Server2019DC" -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy 'Exportable' #-Type SSLServerAuthentication
        $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("Root","LocalMachine")
        ## Open the root certificate store for reading and writing.
        $rootStore.Open("ReadWrite")
        ## Add the certificate stored in the $authenticode variable.
        $rootStore.Add($serverauth)
        ## Close the root certificate store.
        $rootStore.Close()

        $publisherStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("TrustedPublisher","LocalMachine")
        # Open the TrustedPublisher certificate store for reading and writing.
        $publisherStore.Open("ReadWrite")
        ## Add the certificate stored in the $authenticode variable.
        $publisherStore.Add($serverauth)
        ## Close the TrustedPublisher certificate store.
        $publisherStore.Close()

        # Get the code-signing certificate from the local computer's certificate store with the name *ATA Authenticode* and store it to the $codeCertificate variable.
        $codeCertificate = Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.Subject -eq "CN=chef-Server2019DC"}
        return [convert]::tobase64string($codeCertificate[0].rawdata)
      ~
    end
    xit "runs a command to create and retrieve a certificate" do
      # this test is failing on New-SelfSignedCertificate on my 2022 VM
      # but was working on another Windows Server VM
      expect { object.powershell_exec!(cert_script) }.not_to raise_error
    end
  end

end
