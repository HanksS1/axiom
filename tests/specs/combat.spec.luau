--!nocheck
-- Logique de combat : dégâts, parade, armes, postures, validation des tirs.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Damage = H.require("ReplicatedStorage/Shared/Combat/Damage")
	local WeaponLogic = H.require("ReplicatedStorage/Shared/Combat/WeaponLogic")
	local Movement = H.require("ReplicatedStorage/Shared/Combat/Movement")
	local HitValidator = H.require("ServerScriptService/Server/Combat/HitValidator")
	local Fighter = H.require("ServerScriptService/Server/Combat/Fighter")

	local W = Config.Weapons.ranged
	local helmet = function(condition)
		return { uid = "h", itemId = "helmet", condition = condition }
	end

	describe("Damage", function()
		it("dégressivité au-delà de la portée efficace", function()
			expect(Damage.falloff(100, 50)).toBe(1)
			expect(Damage.falloff(100, 100)).toBe(1)
			expect(Damage.falloff(100, 150)).toBeNear(0.75)
			expect(Damage.falloff(100, 200)).toBeNear(0.5)
			expect(Damage.falloff(100, 299)).toBeNear(0.5)
			expect(Damage.falloff(100, 301)).toBe(0)
		end)

		it("dégâts d'arme × état, tête × casque", function()
			local base = { def = W.sentinel_rifle, condition = 4, distance = 10, isHead = false, targetKind = "player" }
			expect(Damage.ranged(base)).toBeNear(17)
			base.condition = 5
			expect(Damage.ranged(base)).toBeNear(17 * 1.15)
			base.condition = 1
			expect(Damage.ranged(base)).toBeNear(17 * 0.7)
			base.condition = 4
			base.isHead = true
			expect(Damage.ranged(base)).toBeNear(34) -- sans casque ×2
			base.helmet = helmet(5)
			expect(Damage.ranged(base)).toBeNear(17 * 1.3)
		end)

		it("pas de multiplicateur de tête pour le rayon et les explosions", function()
			local hit = { def = W.xray_cannon, condition = 4, distance = 5, isHead = true, targetKind = "player" }
			expect(Damage.ranged(hit)).toBeNear(60)
			hit.def = W.short_circuit
			expect(Damage.ranged(hit)).toBeNear(70)
			hit.targetKind = "robot"
			hit.isHead = false
			expect(Damage.ranged(hit)).toBeNear(175) -- ×2,5 contre les robots
		end)

		it("le bouclier absorbe avant les PV", function()
			local r = Damage.apply(100, 70, 50)
			expect(r.shield).toBe(20)
			expect(r.health).toBe(100)
			r = Damage.apply(100, 20, 50)
			expect(r.shield).toBe(0)
			expect(r.health).toBe(70)
			r = Damage.apply(10, 0, 50)
			expect(r.health).toBe(0)
			expect(r.healthDamage).toBe(10)
		end)

		it("lame vibrante : ignore 50 % du bouclier", function()
			local r = Damage.apply(100, 100, 45, 0.5)
			expect(r.shield).toBeNear(100 - 22.5)
			expect(r.health).toBeNear(100 - 22.5)
		end)

		it("ordre de grandeur du temps pour tuer (0,6 à 1,2 s visé)", function()
			-- Fusil de Sentinelle (Bon état) contre 100 PV + gilet Bon état (70).
			local rifle = W.sentinel_rifle
			local shots = math.ceil(170 / rifle.damage)
			local ttk = (shots - 1) / rifle.fireRate
			expect(ttk > 0.6 and ttk < 1.6).toBe(true)
		end)
	end)

	describe("Parade", function()
		local function input(overrides)
			local base = { parrying = true, parryStartedAt = 0, now = 0.1, frontal = true, breaksParry = false }
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("parade parfaite dans les 0,25 s", function()
			expect(Damage.resolveParry(input())).toBe("perfect")
			expect(Damage.parryMultiplier("perfect")).toBe(0)
		end)

		it("garde normale : -60 % de face", function()
			expect(Damage.resolveParry(input({ now = 1 }))).toBe("reduced")
			expect(Damage.parryMultiplier("reduced")).toBeNear(0.4)
		end)

		it("de dos ou sans garde : dégâts pleins", function()
			expect(Damage.resolveParry(input({ frontal = false }))).toBe("none")
			expect(Damage.resolveParry(input({ parrying = false }))).toBe("none")
		end)

		it("le marteau brise la garde", function()
			expect(Damage.resolveParry(input({ breaksParry = true }))).toBe("broken")
			expect(Damage.parryMultiplier("broken")).toBe(1)
		end)

		it("détection de face", function()
			local look = Vector3.new(0, 0, -1)
			local pos = Vector3.new(0, 0, 0)
			expect(Damage.isFrontal(look, pos, Vector3.new(0, 0, -5))).toBe(true)
			expect(Damage.isFrontal(look, pos, Vector3.new(0, 0, 5))).toBe(false)
			expect(Damage.isFrontal(look, pos, Vector3.new(5, 0, -5))).toBe(true) -- 45°
			expect(Damage.isFrontal(look, pos, Vector3.new(5, 0, 0))).toBe(false) -- 90°
		end)
	end)

	describe("WeaponLogic", function()
		it("chargeur : tir, cadence, vide, recharge", function()
			local def = W.scrap_laser_pistol
			local s = WeaponLogic.new(def)
			expect(s.ammo).toBe(12)
			expect(WeaponLogic.canFire(def, s, 0, 30)).toBe(true)
			local r = WeaponLogic.fire(def, s, 0)
			expect(r.projectiles).toBe(1)
			expect(s.ammo).toBe(11)
			local ok, why = WeaponLogic.canFire(def, s, 0.1, 30)
			expect(ok).toBe(false)
			expect(why).toBe("cooldown")
			expect(WeaponLogic.canFire(def, s, 0.34, 30)).toBe(true)
			-- Tolérance serveur (×0,85).
			expect(WeaponLogic.canFire(def, s, 0.29, 30, 0.85)).toBe(true)
			s.ammo = 0
			ok, why = WeaponLogic.canFire(def, s, 10, 30)
			expect(why).toBe("empty")
			expect(WeaponLogic.canReload(def, s, 30)).toBe(true)
			expect(WeaponLogic.canReload(def, s, 0)).toBe(false)
			WeaponLogic.startReload(def, s, 10)
			ok, why = WeaponLogic.canFire(def, s, 10.5, 30)
			expect(why).toBe("reloading")
			expect(WeaponLogic.finishReload(def, s, 11, 30)).toBe(0) -- pas encore fini
			expect(WeaponLogic.finishReload(def, s, 11.6, 5)).toBe(5) -- seulement 5 cellules
			expect(s.ammo).toBe(5)
			expect(s.reloadEndsAt).toBeNil()
		end)

		it("rafale : 3 projectiles par activation (limité par le chargeur)", function()
			local def = W.vigil_pistol
			local s = WeaponLogic.new(def)
			expect(WeaponLogic.fire(def, s, 0).projectiles).toBe(3)
			expect(s.ammo).toBe(21)
			s.ammo = 2
			expect(WeaponLogic.fire(def, s, 1).projectiles).toBe(2)
			expect(s.ammo).toBe(0)
		end)

		it("fusil à pompe : 8 plombs", function()
			local def = W.hullbreaker
			local s = WeaponLogic.new(def)
			expect(WeaponLogic.fire(def, s, 0).projectiles).toBe(8)
			expect(s.ammo).toBe(5)
		end)

		it("surchauffe : mitrailleuse, 1 cellule / 3 tirs, blocage 2,5 s", function()
			local def = W.bastion_minigun
			local s = WeaponLogic.new(def)
			local cells = 0
			local time = 0
			local shots = 0
			while true do
				local ok = WeaponLogic.canFire(def, s, time, 100)
				if not ok then
					break
				end
				local r = WeaponLogic.fire(def, s, time)
				cells += r.cellsConsumed
				shots += 1
				time += 1 / def.fireRate
				if r.overheated then
					break
				end
			end
			expect(shots).toBe(25) -- 25 × 4 = 100 de chaleur
			expect(cells).toBe(8) -- floor(25 / 3)
			local ok, why = WeaponLogic.canFire(def, s, time + 1, 100)
			expect(why).toBe("overheated")
			-- Après le blocage, la chaleur redescend de 30/s.
			WeaponLogic.updateHeat(s, s.overheatedUntil + 1)
			expect(s.heat).toBeNear(70)
			expect(WeaponLogic.canFire(def, s, s.overheatedUntil + 1, 100)).toBe(true)
		end)

		it("refroidissement seulement après 0,4 s sans tirer", function()
			local def = W.short_circuit
			local s = WeaponLogic.new(def)
			WeaponLogic.fire(def, s, 0)
			expect(s.heat).toBe(35)
			WeaponLogic.updateHeat(s, 0.3)
			expect(s.heat).toBe(35)
			WeaponLogic.updateHeat(s, 1.4)
			expect(s.heat).toBeNear(5)
		end)

		it("pas de tir sans cellules (armes à surchauffe)", function()
			local def = W.short_circuit
			local s = WeaponLogic.new(def)
			local ok, why = WeaponLogic.canFire(def, s, 0, 1)
			expect(ok).toBe(false)
			expect(why).toBe("no_cells")
			expect(WeaponLogic.canFire(def, s, 0, 2)).toBe(true)
			expect(WeaponLogic.fire(def, s, 0).cellsConsumed).toBe(2)
		end)
	end)

	describe("Movement", function()
		local function state(overrides)
			local base = { stance = "stand", sprinting = false, parrying = false, stunned = false, speedMultiplier = 1 }
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("vitesses du document (section 5.2)", function()
			expect(Movement.walkSpeed(state())).toBe(14)
			expect(Movement.walkSpeed(state({ sprinting = true }))).toBe(22)
			expect(Movement.walkSpeed(state({ stance = "crouch" }))).toBe(8)
			expect(Movement.walkSpeed(state({ stance = "prone" }))).toBe(4)
			expect(Movement.walkSpeed(state({ stance = "crouch", sprinting = true }))).toBe(8)
			expect(Movement.walkSpeed(state({ parrying = true }))).toBe(7)
			expect(Movement.walkSpeed(state({ sprinting = true, parrying = true }))).toBe(7)
			expect(Movement.walkSpeed(state({ speedMultiplier = 1.2 }))).toBeNear(16.8)
		end)

		it("pas de saut couché", function()
			expect(Movement.jumpHeight(state())).toBe(7)
			expect(Movement.jumpHeight(state({ stance = "prone" }))).toBe(0)
		end)

		it("précision : +15 % accroupi, +30 % couché", function()
			expect(Movement.spread(10, "stand", false, false)).toBeNear(10)
			expect(Movement.spread(10, "crouch", false, false)).toBeNear(8.5)
			expect(Movement.spread(10, "prone", false, false)).toBeNear(7)
		end)
	end)

	describe("HitValidator", function()
		local shooter = { name = "shooter" }
		local target = { name = "target" }
		local head = { Name = "Head", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 1.5, -50) }
		local torso = { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1), Position = Vector3.new(0, 0, -50) }
		local parts = { [head] = target, [torso] = target }

		local function context(overrides)
			local base = {
				now = 100,
				shooterHead = Vector3.new(0, 1.5, 0),
				effectiveRange = 60,
				maxProjectiles = 1,
				findTarget = function(part)
					return parts[part]
				end,
				shooter = shooter,
				castRay = function()
					return nil
				end,
			}
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		local function shot(hits, overrides)
			local base = {
				t = 99.95,
				origin = Vector3.new(0, 1.5, 0),
				direction = Vector3.new(0, 0, -1),
				hits = hits,
			}
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("tir valide à la tête", function()
			local v = HitValidator.validate(shot({ { part = head, position = Vector3.new(0, 1.5, -49.5) } }), context())
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(1)
			expect(v.hits[1].isHead).toBe(true)
			expect(v.hits[1].distance).toBeNear(49.5)
		end)

		it("rejette un tir trop ancien ou daté dans le futur", function()
			expect(HitValidator.validate(shot({}, { t = 98 }), context()).ok).toBe(false)
			expect(HitValidator.validate(shot({}, { t = 101 }), context()).ok).toBe(false)
		end)

		it("rejette une position de tireur incohérente", function()
			local v = HitValidator.validate(shot({}, { origin = Vector3.new(0, 1.5, 30) }), context())
			expect(v.ok).toBe(false)
		end)

		it("rejette trop d'impacts", function()
			local claim = { part = torso, position = Vector3.new(0, 0, -49.5) }
			expect(HitValidator.validate(shot({ claim, claim }), context()).ok).toBe(false)
			expect(HitValidator.validate(shot({ claim, claim }), context({ maxProjectiles = 8 })).ok).toBe(true)
		end)

		it("rejette un impact hors de portée ou loin de la cible", function()
			local far = { Name = "UpperTorso", Size = Vector3.new(2, 2, 1), Position = Vector3.new(0, 0, -400) }
			parts[far] = target
			local v = HitValidator.validate(shot({ { part = far, position = Vector3.new(0, 0, -400) } }), context())
			expect(v.ok).toBe(false)
			v = HitValidator.validate(shot({ { part = torso, position = Vector3.new(0, 0, -20) } }), context())
			expect(v.ok).toBe(false)
		end)

		it("ligne de vue bloquée : impact écarté sans sanction", function()
			local v = HitValidator.validate(
				shot({ { part = torso, position = Vector3.new(0, 0, -49.5) } }),
				context({
					castRay = function()
						return 20
					end,
				})
			)
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(0)
			expect(v.dropped).toBe(1)
		end)

		it("origine du tir derrière un obstacle : impacts écartés", function()
			local v = HitValidator.validate(
				shot({ { part = torso, position = Vector3.new(0, 0, -49.5) } }, { origin = Vector3.new(6, 1.5, 0) }),
				context({
					castRay = function(origin, displacement)
						-- Mur entre la tête (x = 0) et l'origine déclarée (x = 6).
						if displacement.X > 0 and origin.X == 0 then
							return 3
						end
						return nil
					end,
				})
			)
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(0)
			expect(v.dropped).toBe(1)
		end)

		it("ignore le tireur lui-même et les pièces sans propriétaire", function()
			local own = { Name = "Head", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 1.5, 0) }
			parts[own] = shooter
			local stray = { Name = "Wall", Size = Vector3.new(4, 4, 4), Position = Vector3.new(0, 0, -10) }
			local v = HitValidator.validate(
				shot({ { part = own, position = Vector3.new(0, 1.5, 0) } }, {}),
				context({ maxProjectiles = 2 })
			)
			expect(#v.hits).toBe(0)
			v = HitValidator.validate(shot({ { part = stray, position = Vector3.new(0, 0, -10) } }), context())
			expect(#v.hits).toBe(0)
		end)
	end)

	describe("Fighter", function()
		it("réserve de cellules", function()
			local inv = Fighter.simpleInventory({ cell_light = 40 })
			expect(inv:countCells("cell_light")).toBe(40)
			expect(inv:takeCells("cell_light", 12)).toBe(12)
			expect(inv:takeCells("cell_light", 100)).toBe(28)
			expect(inv:countCells("cell_light")).toBe(0)
			expect(inv:takeCells("cell_heavy", 5)).toBe(0)
		end)

		it("cellules comptées depuis le sac", function()
			local cells = Fighter.cellsFromBag({
				{ uid = "a", itemId = "cell_light", stack = 30 },
				{ uid = "b", itemId = "cell_light", stack = 12 },
				{ uid = "c", itemId = "nanite_injector", stack = 3 },
			})
			expect(cells.cell_light).toBe(42)
			expect(cells.nanite_injector).toBeNil()
		end)
	end)
end
