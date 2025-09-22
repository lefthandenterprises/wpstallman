using WPStallman.Core.Classes;



namespace WPStallman.Core.Interfaces;

public interface IPhotinoWindowHandler
{
    public CommandResponse OpenUrl(CommandEnvelope envelope);

    public CommandResponse MaximizeWindow();
    public CommandResponse ShowOpenDialog(CommandEnvelope envelope);
    public CommandResponse ShowSaveDialog(CommandEnvelope envelope);
}
