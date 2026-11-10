{ ... }:
{
  # Border around the focused window.
  services.jankyborders = {
    enable = true;
    width = 4.0;
    hidpi = true;
    style = "round";
    active_color = "0xff89b4fa";
    inactive_color = "0x00000000";
  };
}
