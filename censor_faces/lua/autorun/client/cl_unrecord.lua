-- Censor Faces for NPCs and Ragdolls with Glitch Effect
if CLIENT then
    -- Создаем клиентские переменные для управления эффектами
    local censor_enabled = CreateClientConVar("pp_censor_faces", "0", true, false)
    local censor_size = CreateClientConVar("pp_censor_faces_size", "64", true, false)
    local censor_effect = CreateClientConVar("pp_censor_faces_effect", "mosaic", true, false)
    local censor_regdoll_blur = CreateClientConVar("pp_censor_regdoll_blur", "0", true, false)
    local blur_enabled = CreateClientConVar("pp_blur_enabled", "0", true, false)
    local blur_size_convar = CreateClientConVar("pp_censor_faces_blur_size", "5", true, false)
    local filter_enemy_npcs = CreateClientConVar("pp_censor_faces_enemy_npcs", "0", true, false)

    list.Set("PostProcess", "Censor Faces", {
        icon = "materials/gui/postprocess/censor_faces.jpg",
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
                pp_censor_faces_size = "64",
                pp_censor_faces_effect = "mosaic"
            }

            params.CVars = table.GetKeys(params.Options["#preset.default"])
            CPanel:AddControl("ComboBox", params)

            CPanel:AddControl("CheckBox", { 
                Label = "Enable Censor Faces", 
                Command = "pp_censor_faces" 
            })


            CPanel:AddControl("ComboBox", {
                Label = "Censor Effect",
                Command = "pp_censor_faces_effect",
                Options = {
                    ["Mosaic"] = { pp_censor_faces_effect = "mosaic" },
                    ["Black Square"] = { pp_censor_faces_effect = "square" },
                    ["White Square"] = { pp_censor_faces_effect = "white Square" },
                    ["Glitch"] = { pp_censor_faces_effect = "glitch" }
                }
            })

            CPanel:AddControl("CheckBox", { 
                Label = "Apply Blur to Ragdolls", 
                Command = "pp_censor_regdoll_blur" 
            })
            
            -- Кнопка для включения/отключения ползунка
            CPanel:AddControl("CheckBox", { 
                Label = "Enable Blur Size Slider", 
                Command = "pp_blur_enabled" 
            })

            -- Ползунок для размера блюра
            CPanel:AddControl("Slider", {
                Label = "Blur Size",
                Command = "pp_censor_faces_blur_size",
                Type = "Float",
                Min = "0",
                Max = "10",
                Description = "Adjust the size of the blur effect."
            })

            -- Фильтр по врагам
            CPanel:AddControl("CheckBox", { 
                Label = "Filter Enemy NPCs Only", 
                Command = "pp_censor_faces_enemy_npcs" 
    
            })

            CPanel:AddControl("Label", {
              Text = "This addon is a modification of the original add-on Censored Faces of the Players from RG Studio. In this version, the method of handling censorship was changed, allowing it to be adapted for use on the faces of non-player characters (NPCs). Version 1.4B"
            })

        end
    })

    local dscale = ScrH() / 8
    local tex = GetRenderTarget("Unrecord_CensorFaces_RT_"..dscale, dscale * ScrW() / ScrH(), dscale)
    local mat = CreateMaterial("Unrecord_CensorFaces_RT"..dscale, "UnlitGeneric", {
        ["$basetexture"] = tex:GetName()
    })

    local blurMaterial = Material("pp/blurscreen")

    -- Список классов врагов
    local enemy_classes = {
        "npc_combine_s", "npc_combine_camera", "npc_combinegunship",
        "npc_metropolice", "npc_zombie", "npc_fastzombie",
        "npc_poisonzombie", "npc_antlion", "npc_antlion_worker",
        "npc_antlionguard", "npc_strider", "npc_turret_floor", "npc_turret_ceiling",
        "npc_turret_ground", "npc_manhack", "npc_rollermine"
    }

    local function isEnemyNPC(npc)
        local class = npc:GetClass()
        for _, enemy_class in ipairs(enemy_classes) do
            if class == enemy_class then
                return true
            end
        end
        return false
    end

    hook.Add("RenderScreenspaceEffects", "Unrecord_CensorFaces_PostProcess", function()
        if not censor_enabled:GetBool() then return end

        local effect_type = censor_effect:GetString()
        local apply_blur_to_regdolls = censor_regdoll_blur:GetBool()
        local blur_slider_enabled = blur_enabled:GetBool()
        local blur_size = blur_slider_enabled and blur_size_convar:GetFloat() or 1.15
        local filter_enemy_npcs = filter_enemy_npcs:GetBool()

        for _, entity in ipairs(ents.GetAll()) do
            local is_npc = entity:IsNPC()
            local is_regdoll = entity:IsRagdoll()

            if filter_enemy_npcs and is_npc then
                if not isEnemyNPC(entity) then
                    is_npc = false
                end
            end

            if is_npc or (is_regdoll and apply_blur_to_regdolls) then
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

                if entity.unrec_head_set and entity.unrec_head_bone then
                    render.CopyRenderTargetToTexture(tex)

                    cam.Start2D()
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

                        -- Трассировка для проверки, что нет объектов между камерой и головой
                        local tr = util.TraceLine({
                            start = LocalPlayer():EyePos(),
                            endpos = pos,
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
                        local size = math.max(xdiff, ydiff) * 1 / entity:EyePos():Distance(LocalPlayer():EyePos()) * (ScrH() / 8) * blur_size

                        -- Применение эффекта
                        if effect_type == "square" then
                            draw.RoundedBox(0, data2D.x - size, data2D.y - size, size * 2, size * 2, Color(0, 0, 0))
                        elseif effect_type == "mosaic" then
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
                        elseif effect_type == "white Square" then
                            draw.RoundedBox(0, data2D.x - size, data2D.y - size, size * 2, size * 2, Color(255, 255, 255))
                        elseif effect_type == "glitch" then
                            local glitch_size = size * 0.8
                            local glitch_count = math.ceil(85)

                            -- Основной глитч эффект
                            for i = 1, glitch_count do
                                local offsetX = math.random(-glitch_size, glitch_size)
                                local offsetY = math.random(-glitch_size, glitch_size)
                                local glitch_rect_width = math.random(size * 0.2, size * 0.5)
                                local glitch_rect_height = math.random(size * 0.2, size * 0.5)

                                -- Генерация случайного цвета и альфа-канала
                                local random_color = Color(math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255))
                                
                                draw.RoundedBox(0, data2D.x + offsetX, data2D.y + offsetY, glitch_rect_width, glitch_rect_height, random_color)
                            end

                            -- Добавление дергания
                            local current_time = CurTime()
                            local time_factor = (current_time % 1)
                            local offset_factor = math.sin(time_factor * 2 * math.pi) * glitch_size * 0.05

                            -- Применение искажений
                            for i = 1, glitch_count do
                                local offsetX = math.random(-glitch_size, glitch_size) + offset_factor
                                local offsetY = math.random(-glitch_size, glitch_size) + offset_factor
                                local glitch_rect_width = math.random(size * 0.2, size * 0.5)
                                local glitch_rect_height = math.random(size * 0.2, size * 0.5)
                                -- Генерация случайного цвета и альфа-канала
                                local random_color = Color(math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(50, 150))
                                
                                draw.RoundedBox(0, data2D.x + offsetX, data2D.y + offsetY, glitch_rect_width, glitch_rect_height, random_color)
                            end
                        end
                    cam.End2D()
                end
            end
        end
    end)
end
