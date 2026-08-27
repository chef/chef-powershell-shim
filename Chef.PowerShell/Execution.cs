using System.Collections.Generic;

namespace Chef
{
    public partial class PowerShell
    {
        /// <summary>
        /// Object that contains the execution result and any errors.
        /// </summary>
        public class Execution
        {
            /// <summary>
            /// Contains a JSON representation of the result.
            /// </summary>
            public string result { get; set; }

            /// <summary>
            /// An array containing the errors.
            /// </summary>
            public List<string> errors { get; set; } = new List<string>();

            /// <summary>
            /// An array containing the verbose text.
            /// </summary>
            public List<string> verbose { get; set; } = new List<string>();
        }
    }
}
