client {
  template {
    #Remove blacklist in order for allow "plugins" to run. We need curl to run as a plugin in template
    plugin_blacklist = []
  }
}