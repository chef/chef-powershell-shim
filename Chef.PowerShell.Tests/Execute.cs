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
            var output = JObject.Parse(instance.Execute("get-item c:\\"));
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
            var output = JObject.Parse(instance.Execute(lines));
            Assert.AreEqual("C:\\", output["FullName"].ToString());
        }

        [TestMethod]
        public void Execute_with_single_line_command_raw()
        {
            var instance = new PowerShell();
            var output = instance.Execute("get-item c:\\", true);
            Assert.AreEqual("C:\\", output);
        }

        [TestMethod]
        public void Execute_with_multi_line_command_raw()
        {
            var instance = new PowerShell();
            var lines = @"
            $a = ""Chef""
            $b = "" ""
            $c = ""Software""
            ""$a$b$c""
            ";
            var output = instance.Execute(lines, true);
            Assert.AreEqual("Chef Software", output);
        }
    }
}
