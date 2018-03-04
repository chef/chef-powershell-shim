using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Newtonsoft.Json.Linq;
using Microsoft.CSharp;
using Newtonsoft.Json;

namespace Chef
{
    [TestClass]
    public class PowerShellTests
    {
        [TestMethod]
        public void Execute_with_single_line_command()
        {
            var instance = new PowerShell();
            var output = instance.ExecuteScript("$PSVersionTable");
            Assert.IsTrue(output.Contains("PSVersion"));
        }

        [TestMethod]
        public void Execute_with_multi_line_command()
        {
            var instance = new PowerShell();
            var lines = @"
            $a = ""c:\\""
            get-item $a
            ";
            var output = instance.ExecuteScript(lines);
            Assert.IsTrue(output.Contains("FullName"));
            Assert.IsTrue(output.Contains("C:\\"));
        }

        [TestMethod]
        public void Execute_with_no_results()
        {
            var instance = new PowerShell();
            var lines = @"
            get-module
            ";
            var output = JsonConvert.DeserializeObject(instance.ExecuteScript(lines));
            Assert.AreEqual("{}", ((Newtonsoft.Json.Linq.JValue)((Newtonsoft.Json.Linq.JProperty)((Newtonsoft.Json.Linq.JContainer)output).First).Value).Value);
        }
    }
}
