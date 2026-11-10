using Meadow.Hardware;
using Meadow.Logging;

namespace FieldKit.Meadow.Services
{
    public class NetworkService : BaseService
    {
        private readonly DiagnosticsService diagnosticsService;

        public NetworkService(Logger logger,
            DiagnosticsService diagnosticsService) : base(logger)
        {
            this.diagnosticsService = diagnosticsService;
        }

        public void NetworkIsConnected(INetworkAdapter sender)
        {
            diagnosticsService.OutputDeviceWifiInfo(sender);
        }
    }
}
