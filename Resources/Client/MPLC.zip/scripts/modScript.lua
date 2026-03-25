log('I', 'srs_loading', 'modScript.lua executed')
if extensions and extensions.load then
  extensions.load("srs_loading")
else
  load("srs_loading")
end
setExtensionUnloadMode("srs_loading", "auto")
