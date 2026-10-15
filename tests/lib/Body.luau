--!nocheck
--[[
	Body : mannequin R15 « bloc » standard et tests de volumes, pour vérifier
	les postures des armes hors de Studio (tests et outil de réglage).

	Repère : celui du haut du torse (UpperTorso), comme les Transform des
	joints posés par WeaponPoseController.
]]

local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local Body = {}

-- Dimensions d'un avatar R15 « bloc » (échelle 1).
Body.torsoSize = Vector3.new(2, 1.6, 1)

-- Bras : épaule au bord du torse, haut du bras décalé vers l'extérieur.
function Body.arm(sign: number)
	return {
		shoulderC0 = CFrame.new(sign * 1, 0.563, 0),
		shoulderC1 = CFrame.new(-sign * 0.5, 0.42, 0),
		elbowC0 = CFrame.new(0, -0.334, 0),
		elbowC1 = CFrame.new(0, 0.2, 0),
		wristC0 = CFrame.new(0, -0.501, 0),
		wristC1 = CFrame.new(0, 0.125, 0),
	}
end

Body.right = Body.arm(1)
Body.left = Body.arm(-1)

-- Pièces du bras d'après les Transform (comme le moteur : Part0 * C0 * T * C1⁻¹).
function Body.forward(rig, shoulder, elbow, wrist)
	local upper = rig.shoulderC0 * shoulder * rig.shoulderC1:Inverse()
	local lower = upper * rig.elbowC0 * elbow * rig.elbowC1:Inverse()
	local hand = lower * rig.wristC0 * wrist * rig.wristC1:Inverse()
	return upper, lower, hand
end

--[[
	Volumes du corps qu'une arme ne doit pas traverser, repère du haut du
	torse : le torse lui-même, la tête et le bas du torse (tournés par les
	rotations ajoutées au cou et à la taille). `waist` / `neck` : celles de la
	pose (nil = aucune).
]]
function Body.volumes(waist, neck)
	local volumes = {
		{ name = "torse", cframe = CFrame.new(), size = Body.torsoSize },
	}
	-- Tête : au-dessus du cou, tournée par le cou.
	local neckJoint = CFrame.new(0, 0.8, 0) * (neck or CFrame.new())
	table.insert(
		volumes,
		{ name = "tête", cframe = neckJoint * CFrame.new(0, 0.6, 0), size = Vector3.new(1.2, 1.2, 1.2) }
	)
	-- Bas du torse : sous la taille ; la taille tourne le haut du torse, donc
	-- le bas tourne à l'inverse vu du haut.
	local waistJoint = CFrame.new(0, -0.8, 0) * (waist or CFrame.new()):Inverse()
	table.insert(
		volumes,
		{ name = "bassin", cframe = waistJoint * CFrame.new(0, -0.2, 0), size = Vector3.new(2, 0.4, 1) }
	)
	return volumes
end

-- Profondeur d'interpénétration de deux boîtes orientées (0 si elles ne se touchent pas).
function Body.penetration(aFrame, aSize, bFrame, bSize)
	local aAxes = { aFrame.XVector, aFrame.YVector, aFrame.ZVector }
	local bAxes = { bFrame.XVector, bFrame.YVector, bFrame.ZVector }
	local aHalf = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local bHalf = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local offset = bFrame.Position - aFrame.Position
	local axes = {}
	for _, axis in aAxes do
		table.insert(axes, axis)
	end
	for _, axis in bAxes do
		table.insert(axes, axis)
	end
	for _, a in aAxes do
		for _, b in bAxes do
			local cross = a:Cross(b)
			if cross.Magnitude > 1e-4 then
				table.insert(axes, cross.Unit)
			end
		end
	end
	local depth = math.huge
	for _, axis in axes do
		local ra, rb = 0, 0
		for i = 1, 3 do
			ra += aHalf[i] * math.abs(aAxes[i]:Dot(axis))
			rb += bHalf[i] * math.abs(bAxes[i]:Dot(axis))
		end
		local overlap = ra + rb - math.abs(offset:Dot(axis))
		if overlap <= 0 then
			return 0
		end
		depth = math.min(depth, overlap)
	end
	return depth
end

--[[
	Plus forte interpénétration entre une arme posée (`weaponFrame` : pièce
	« Body », repère du torse) et le corps. Retourne la profondeur, la pièce
	de l'arme et le volume touché.
]]
function Body.weaponPenetration(blueprint, weaponFrame, waist, neck)
	local worst, part, volume = 0, nil, nil
	for _, spec in blueprint.parts do
		local frame = weaponFrame * spec.cframe
		for _, v in Body.volumes(waist, neck) do
			local depth = Body.penetration(frame, spec.size, v.cframe, v.size)
			if depth > worst then
				worst, part, volume = depth, spec.name, v.name
			end
		end
	end
	return worst, part, volume
end

return Body
