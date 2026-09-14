log('I', "[EconomyUI] modScript", "modScript.lua LOADED")

load("key")
setExtensionUnloadMode("key", "manual")

load("minimap")
setExtensionUnloadMode("minimap", "manual")

load("PartsShop")
setExtensionUnloadMode("PartsShop", "manual")

load("powerUpsClient")
setExtensionUnloadMode("powerUpsClient", "manual")

load("mybollard")
setExtensionUnloadMode("mybollard", "manual")

load("PartsDisplay")
setExtensionUnloadMode("PartsDisplay", "manual")

extensions.core_input_categories.uimpit = {
    order = 700,
    icon  = "extension",
    title = "PIT",
    desc  = "PIT Economy Server Controls"
}

print("[EconomyUI] modScript.lua LOADED")

