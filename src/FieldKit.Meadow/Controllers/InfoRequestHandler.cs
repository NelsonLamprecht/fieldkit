using System.Diagnostics.CodeAnalysis;
using Meadow;
using Meadow.Foundation.Web.Maple;
using Meadow.Foundation.Web.Maple.Routing;

namespace FieldKit.Meadow.Controllers
{
    /// <summary>
    /// GET /info on every device: its name, kind and version as JSON. Maple finds request handlers by
    /// scanning the loaded assemblies, so this one is picked up in each app just by referencing
    /// FieldKit.Meadow.
    /// </summary>
    public class InfoRequestHandler : RequestHandlerBase
    {
        // Maple keeps per-request state (QueryString, Context) on the handler, so never share one
        public override bool IsReusable => false;

        [HttpGet("/info")]
        [SuppressMessage("Performance", "CA1822:Mark members as static", Justification = "Maple routes to instance methods.")]
        public IActionResult Info()
        {
            var name = Resolver.Device.Information.DeviceName;
            Resolver.Log.Info($"Info request: {name}, {DeviceInfo.Type}, {DeviceInfo.Version}.");

            return new ContentResult(DeviceInfo.ToJson(name), "application/json");
        }
    }
}
