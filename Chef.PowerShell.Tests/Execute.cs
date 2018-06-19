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
            var output = PowerShell.ExecuteScript("$PSVersionTable");
            Assert.IsTrue(output.Contains("PSVersion"));
        }

        [TestMethod]
        public void Execute_with_multi_line_command()
        {
            var lines = @"
            $a = ""c:\\""
            get-item $a
            ";
            var output = PowerShell.ExecuteScript(lines);
            Assert.IsTrue(output.Contains("FullName"));
            Assert.IsTrue(output.Contains("C:\\"));
        }

        [TestMethod]
        public void Execute_with_single_line_command_not_null()
        {
            var instance = new PowerShell();
            var output = PowerShell.ExecuteScript("get-service");
            Console.WriteLine(output);
            Assert.IsNotNull(output);
        }

        [TestMethod]
        public void Execute_with_no_results()
        {
            var lines = @"
            get-module
            ";
            var output = JsonConvert.DeserializeObject(PowerShell.ExecuteScript(lines));
            Assert.AreEqual("{}", ((Newtonsoft.Json.Linq.JValue)((Newtonsoft.Json.Linq.JProperty)((Newtonsoft.Json.Linq.JContainer)output).First).Value).Value);
        }
    }
}
