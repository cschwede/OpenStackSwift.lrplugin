local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrDigest = import 'LrDigest'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrStringUtils = import 'LrStringUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local bind = LrView.bind
local provider = {}

provider.hidePrintResolution = true
provider.canExportVideo = true
provider.hideSections = { 'exportLocation', }

provider.exportPresetFields = {
    { key = 'key' },
    { key = 'url' },
}


function provider.sectionsForTopOfDialog(f, propertyTable)
    local result = {
        {
            title = "OpenStack Swift Storage settings",

            f:row {
                fill_horizonal = 1,
                spacing = f:label_spacing(),
                f:static_text {
                    title = "Storage URL",
                    alignment = 'right',
                    width = LrView.share('label_width'),
                },
                f:edit_field {
                    value = bind 'url',
                    fill_horizontal = 1,
                },
            },

            f:row {
                fill_horizonal = 1,
                spacing = f:label_spacing(),
                f:static_text {
                    title = "tempurl key",
                    alignment = 'right',
                    width = LrView.share('label_width'),
                },
                f:password_field {
                    value = bind 'key',
                    fill_horizontal = 1,
                },
            },

        }
    }    
    return result
end        


function provider.processRenderedPhotos(functionContext, exportContext)
    local exportSession = exportContext.exportSession

    local exportSettings = assert(exportContext.propertyTable)
    local nPhotos = exportSession:countRenditions()

    local progressScope = exportContext:configureProgress {
        title = "Exporting..."
    }

    for i, rendition in exportContext:renditions { stopIfCanceled = true } do
        if progressScope:isCanceled() then break end

        local obj_name = LrPathUtils.leafName(rendition.destinationPath)

        if not rendition.wasSkipped then
            local success, pathOrMessage = rendition:waitForRender()
            if not success then
                rendition:uploadFailed("Unable to render image")
                return
            end

            local success, content = pcall(LrFileUtils.readFile, pathOrMessage)

            if not success then
                rendition:uploadFailed("Unable to read rendered file")
                return
            end

            local content_type = 'image/jpeg'
            if not LrPathUtils.extension(rendition.destinationPath) == "jpg" then
                content_type = 'application/binary'
            end

            local title = rendition.photo:getFormattedMetadata('title')
            local caption = rendition.photo:getFormattedMetadata('caption')
            local headers = {{field = 'content-type', value = content_type},
                             {field = 'X-Object-Meta-Title', value = title},
                             {field = 'X-Object-Meta-Caption', value = caption}}

            local url, path = uploadPhoto(exportSettings, obj_name, content, headers)

            if not url then
                rendition:uploadFailed("Unable to upload rendered file")
                return
            end

        end

        progressScope:setPortionComplete(i, nPhotos)
    end

    progressScope:done()
end


local function tempurl(url, key, method)
    local expires = tostring(os.time() + 900)

    local path = url:match( ".*(/v1/.*)$" )

    local hmac_body = string.format("%s\n%s\n%s", method, expires, path)

    local signature = LrDigest.HMAC.digest(hmac_body, 'SHA1', key)

    return string.format("%s?temp_url_sig=%s&temp_url_expires=%s", url, signature, expires)
end


function uploadPhoto(settingsTable, objname, content, headers)
    local url = string.format("%s/%s", settingsTable.url, objname)
    local signed_url = tempurl(url, settingsTable.key, "PUT")

    local result, hdrs = LrHttp.post(signed_url, content, headers, "PUT")

    if not result then
        LrErrors.throwUserError("Connection failed.")
    end

    if hdrs.status ~= 201 then
        LrErrors.throwUserError(result)
    end

    return signed_url, path
end


return provider
