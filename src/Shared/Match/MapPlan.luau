--!strict
--[[
	MapPlan : plan vu de dessus d'une carte (module PUR).

	Le serveur le calcule une fois à partir de la description de la carte
	(LayoutBuilder) : une grille d'occupation des obstacles à hauteur d'homme
	(murs, piliers, gros décors), regroupée en rectangles et encodée dans une
	chaîne compacte. Le client la décode pour dessiner la carte (touche
	« carte ») : quelques centaines de rectangles, créés une seule fois.

	Coordonnées : `u`, `v` de 0 à 1 sur le plan (u = axe X, v = axe Z), le
	centre de la carte étant à (0,5 ; 0,5). Le nord (Z négatif) est en haut.
]]

local MapPlan = {}

export type Rect = { x: number, z: number, w: number, d: number } -- en cases
export type Plan = { cells: number, rects: { Rect } }
export type Solid = { size: Vector3, cframe: CFrame, collide: boolean? }
export type Band = { min: number, max: number, minSpan: number? }

-- Emprise au sol et hauteurs d'une pièce (boîte englobante alignée sur les axes).
local function boundsOf(part: Solid): (number, number, number, number, number, number)
	local size, cframe = part.size, part.cframe
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
	local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
	local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
	local p = cframe.Position
	return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
end

--[[
	Grille d'occupation (`cells` × `cells` booléens, ligne par ligne) : une case
	est pleine si un obstacle solide traverse la tranche de hauteur `band`.
	Le sol et les très grandes dalles (plus de la moitié de la carte) sont
	ignorés, ainsi que le petit décor (plus court que `band.minSpan`) : le plan
	doit montrer les murs et les masses, pas chaque baril.
]]
function MapPlan.rasterize(parts: { Solid }, size: number, cell: number, band: Band): ({ boolean }, number)
	local cells = math.ceil(size / cell)
	local grid = table.create(cells * cells, false)
	local half = size / 2
	local minSpan = band.minSpan or 0
	for _, part in parts do
		if part.collide == false then
			continue
		end
		local x0, x1, y0, y1, z0, z1 = boundsOf(part)
		if y1 <= band.min or y0 >= band.max then
			continue
		end
		if x1 - x0 > size * 0.5 and z1 - z0 > size * 0.5 then
			continue
		end
		if math.max(x1 - x0, z1 - z0) < minSpan then
			continue
		end
		local cx0 = math.clamp(math.floor((x0 + half) / cell), 0, cells - 1)
		local cx1 = math.clamp(math.ceil((x1 + half) / cell) - 1, 0, cells - 1)
		local cz0 = math.clamp(math.floor((z0 + half) / cell), 0, cells - 1)
		local cz1 = math.clamp(math.ceil((z1 + half) / cell) - 1, 0, cells - 1)
		if x1 < -half or x0 > half or z1 < -half or z0 > half then
			continue
		end
		for cz = cz0, cz1 do
			local row = cz * cells
			for cx = cx0, cx1 do
				grid[row + cx + 1] = true
			end
		end
	end
	return grid, cells
end

-- Regroupe les cases pleines en rectangles (parcours glouton : large d'abord, puis haut).
function MapPlan.rects(grid: { boolean }, cells: number): { Rect }
	local used = table.create(cells * cells, false)
	local rects: { Rect } = {}
	for cz = 0, cells - 1 do
		for cx = 0, cells - 1 do
			local index = cz * cells + cx + 1
			if not grid[index] or used[index] then
				continue
			end
			local w = 1
			while cx + w < cells and grid[index + w] and not used[index + w] do
				w += 1
			end
			local d = 1
			while cz + d < cells do
				local row = (cz + d) * cells + cx + 1
				local full = true
				for offset = 0, w - 1 do
					if not grid[row + offset] or used[row + offset] then
						full = false
						break
					end
				end
				if not full then
					break
				end
				d += 1
			end
			for dz = 0, d - 1 do
				local row = (cz + dz) * cells + cx + 1
				for offset = 0, w - 1 do
					used[row + offset] = true
				end
			end
			table.insert(rects, { x = cx, z = cz, w = w, d = d })
		end
	end
	return rects
end

function MapPlan.build(parts: { Solid }, size: number, cell: number, band: Band): Plan
	local grid, cells = MapPlan.rasterize(parts, size, cell, band)
	return { cells = cells, rects = MapPlan.rects(grid, cells) }
end

-- « cases|x,z,l,p;x,z,l,p;… »
function MapPlan.encode(plan: Plan): string
	local pieces = table.create(#plan.rects)
	for index, rect in plan.rects do
		pieces[index] = `{rect.x},{rect.z},{rect.w},{rect.d}`
	end
	return `{plan.cells}|{table.concat(pieces, ";")}`
end

-- Plan décodé, ou nil si la chaîne est invalide (jamais d'erreur : donnée reçue du réseau).
function MapPlan.decode(text: any): Plan?
	if type(text) ~= "string" then
		return nil
	end
	local head, body = string.match(text, "^(%d+)|(.*)$")
	local cells = tonumber(head)
	if cells == nil or body == nil or cells < 1 or cells > 1024 then
		return nil
	end
	local rects: { Rect } = {}
	for x, z, w, d in string.gmatch(body, "(%d+),(%d+),(%d+),(%d+)") do
		local rect = {
			x = tonumber(x) :: number,
			z = tonumber(z) :: number,
			w = tonumber(w) :: number,
			d = tonumber(d) :: number,
		}
		if rect.w < 1 or rect.d < 1 or rect.x + rect.w > cells or rect.z + rect.d > cells then
			return nil
		end
		table.insert(rects, rect)
	end
	return { cells = cells, rects = rects }
end

-- Position du monde → coordonnées du plan (0 à 1), et si le point est dans la carte.
function MapPlan.toPlan(position: Vector3, origin: Vector3, size: number): (number, number, boolean)
	local u = (position.X - origin.X) / size + 0.5
	local v = (position.Z - origin.Z) / size + 0.5
	return u, v, u >= 0 and u <= 1 and v >= 0 and v <= 1
end

-- Coordonnées du plan → position du monde (au niveau du sol de la carte).
function MapPlan.toWorld(u: number, v: number, origin: Vector3, size: number): Vector3
	return Vector3.new(origin.X + (u - 0.5) * size, origin.Y, origin.Z + (v - 0.5) * size)
end

return MapPlan
