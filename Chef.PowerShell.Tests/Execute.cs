using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Newtonsoft.Json.Linq;

namespace Chef
{
    [TestClass]
    public class PowerShellTests
    {
        [TestMethod]
        public void Execute_with_single_line_command()
        {
            var instance = new PowerShell();
            var output = JObject.Parse(instance.ExecuteScript("get-item c:\\"));
            Assert.AreEqual("C:\\", output["FullName"].ToString());
        }

        [TestMethod]
        public void Execute_with_multi_line_command()
        {
            var instance = new PowerShell();
            var lines = @"
            $a = ""c:\\""
            get-item $a
            ";
            var output = JObject.Parse(instance.ExecuteScript(lines));
            Assert.AreEqual("C:\\", output["FullName"].ToString());
        }

        [TestMethod]
        public void Execute_with_no_results()
        {
            var instance = new PowerShell();
            var lines = @"
            get-module
            ";
            var output = JObject.Parse(instance.ExecuteScript(lines));
            Assert.AreEqual("{}", output.ToString());
        }

        [TestMethod]
        public void Execute_with_multiple_output_lines()
        {
            var instance = new PowerShell();
            var lines = @"
            Write-Output ""Chef""
            Write-Output ""Software""
            ";
            var output = JArray.Parse(instance.ExecuteScript(lines));
            Assert.AreEqual("Chef", output[0].ToString());
            Assert.AreEqual("Software", output[1].ToString());
        }
    }
}
