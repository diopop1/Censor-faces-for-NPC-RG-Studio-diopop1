-- censor_faces\lua\autorun\client\cl_unrecord.lua

if CLIENT then
    -- Создаем клиентские переменные для управления эффектом
    local censor_enabled = CreateClientConVar("pp_censor_faces", "0", true, false)
    local censor_size = CreateClientConVar("pp_censor_faces_size", "64", true, false)

    -- Регистрируем эффект в меню постобработки
    list.Set("PostProcess", "Censor Faces", {
        icon = "materials/gui/postprocess/censor_faces.jpg", -- Убедитесь, что иконка доступна по этому пути
        convar = "pp_censor_faces",
        category = "#shaders_pp",
        cpanel = function(CPanel)
            local params = {
                Options = {},
                CVars = {},
                MenuButton = "1",
                Folder = "censor_faces"
            }

            params.Options["#preset.default"] = {
                pp_censor_faces_size = "64"
            }   

            params.CVars = table.GetKeys(params.Options["#preset.default"])
            CPanel:AddControl("ComboBox", params)

            CPanel:AddControl("CheckBox", { 
                Label = "Enable Censor Faces", 
                Command = "pp_censor_faces" 
            })

        end
    })

    local dscale = ScrH() / 8
    local tex = GetRenderTarget("Unrecord_CensorFaces_RT_"..dscale, dscale * ScrW() / ScrH(), dscale)
    local mat = CreateMaterial("Unrecord_CensorFaces_RT"..dscale, "UnlitGeneric", {
        ["$basetexture"] = tex:GetName()
    })

    -- Хук для постобработки
    hook.Add("RenderScreenspaceEffects", "Unrecord_CensorFaces_PostProcess", function()
        if not censor_enabled:GetBool() then return end

        -- Используем постобработку для размывания лиц НПС
        for _, entity in ipairs(ents.GetAll()) do
            if entity:IsNPC() then
                -- Устанавливаем флаг рендеринга
                local rendering = true

                -- Убедитесь, что голова НПС установлена
                if not entity.unrec_head_set then
                    local numHitBoxSets = entity:GetHitboxSetCount()
                    local set, bone = 0, 0
                    for hboxset = 0, numHitBoxSets - 1 do
                        local numHitBoxes = entity:GetHitBoxCount(hboxset)
                        for hitbox = 0, numHitBoxes - 1 do
                            if entity:GetBoneName(entity:GetHitBoxBone(hitbox, hboxset)) == "ValveBiped.Bip01_Head1" then
                                set = hboxset
                                bone = hitbox
                                break
                            end
                        end
                    end
                    entity.unrec_head_set, entity.unrec_head_bone = set, bone
                end

                -- Проверьте, что переменные не равны nil
                if entity.unrec_head_set and entity.unrec_head_bone then
                    -- Копируем текущее изображение в текстуру
                    render.CopyRenderTargetToTexture(tex)

                    cam.Start2D()
                        -- Проверяем, существует ли компонент "eyes"
                        local attachment = entity:LookupAttachment("eyes")
                        if attachment == 0 then
                            cam.End2D()
                            continue
                        end
                        local angpos = entity:GetAttachment(attachment)
                        if not angpos then
                            cam.End2D()
                            continue
                        end

                        local pos, eye_angles = angpos.Pos, angpos.Ang
                        local data2D = pos:ToScreen()
                        if not data2D.visible then
                            cam.End2D()
                            continue
                        end

                        local tr = util.TraceLine({
                            start = LocalPlayer():EyePos(),
                            endpos = entity:EyePos(),
                            filter = function(ent) return ent ~= entity and ent ~= LocalPlayer() end
                        })
                        if tr.Hit then
                            cam.End2D()
                            continue
                        end
                        if eye_angles:Forward():Dot(EyeAngles():Forward()) > 0.89 then
                            cam.End2D()
                            continue
                        end

                        -- Проверяем, есть ли у НПС правильные хитбоксы
                        local mins, maxs = entity:GetHitBoxBounds(entity.unrec_head_bone, entity.unrec_head_set)
                        if not mins or not maxs then
                            cam.End2D()
                            continue
                        end

                        mins = mins + entity:GetPos()
                        maxs = maxs + entity:GetPos()

                        cam.Start3D(entity:EyePos() + entity:EyeAngles():Forward() * 160, (-entity:EyeAngles():Forward()):Angle())
                            local mins_toscreen, maxs_toscreen = mins:ToScreen(), maxs:ToScreen()
                        cam.End3D()

                        local maxxy, minxy = {}, {}
                        maxxy.x = math.max(maxs_toscreen.x, mins_toscreen.x)
                        maxxy.y = math.max(maxs_toscreen.y, mins_toscreen.y)
                        minxy.x = math.min(maxs_toscreen.x, mins_toscreen.x)
                        minxy.y = math.min(mins_toscreen.y, maxs_toscreen.y)
                        local xdiff, ydiff = math.abs(maxxy.x - minxy.x), math.abs(maxxy.y - minxy.y)
                        local size = math.max(xdiff, ydiff) * 1 / entity:EyePos():Distance(LocalPlayer():EyePos()) * ScrH() / 8

                        render.SetStencilWriteMask(0xFF)
                            render.SetStencilTestMask(0xFF)
                            render.SetStencilReferenceValue(1)
                            render.SetStencilPassOperation(STENCIL_KEEP)
                            render.SetStencilZFailOperation(STENCIL_KEEP)
                            render.ClearStencil()
                            render.SetStencilCompareFunction(STENCIL_NEVER)
                            render.SetStencilFailOperation(STENCIL_REPLACE)
                        render.SetStencilEnable(true)
                            draw.RoundedBox(0, data2D.x - size, data2D.y - size, size * 2, size * 2, Color(0, 0, 0))
                            render.SetStencilCompareFunction(STENCIL_EQUAL)
                            render.SetStencilFailOperation(STENCIL_REPLACE)
                            render.PushFilterMin(1)
                            render.PushFilterMag(1)
                            render.DrawTextureToScreen(tex)
                            render.PopFilterMin()
                            render.PopFilterMag()
                        render.SetStencilEnable(false)
                    cam.End2D()
                end

                -- Сбрасываем флаг рендеринга
                rendering = false
            end
        end
    end)
end
