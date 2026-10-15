--!nocheck
-- Caisse gratuite : déroulé de l'ouverture côté client (annulation, refus, délai).

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local FreeCrateFlow = H.require("ReplicatedStorage/Shared/Economy/FreeCrateFlow")

	describe("Ouverture de la caisse gratuite", function()
		it("animation seulement si une caisse est disponible et l'économie ouverte", function()
			local flow = FreeCrateFlow.new()
			expect(FreeCrateFlow.decide(flow, 1, false, false)).toBe("animate")
			-- En file d'attente ou en partie : le serveur refuserait, pas d'animation bloquante.
			expect(FreeCrateFlow.decide(flow, 1, true, false)).toBe("direct")
			expect(FreeCrateFlow.decide(flow, 0, false, false)).toBe("direct")
			expect(FreeCrateFlow.decide(flow, 1, false, true)).toBe("direct")
		end)

		it("une seule ouverture à la fois", function()
			local flow = FreeCrateFlow.new()
			FreeCrateFlow.start(flow)
			expect(FreeCrateFlow.decide(flow, 2, false, false)).toBe("busy")
			FreeCrateFlow.sent(flow, 10)
			expect(FreeCrateFlow.decide(flow, 2, false, false)).toBe("busy")
			FreeCrateFlow.shown(flow)
			expect(FreeCrateFlow.decide(flow, 2, false, false)).toBe("animate")
		end)

		it("départ en partie pendant l'animation : la demande différée n'est jamais envoyée", function()
			local flow = FreeCrateFlow.new()
			local session = FreeCrateFlow.start(flow)
			expect(FreeCrateFlow.isCurrent(flow, session)).toBe(true)
			FreeCrateFlow.cancel(flow) -- la partie démarre
			-- La suite différée de l'animation se réveille : périmée, elle n'envoie rien
			-- (la caisse n'a pas été demandée au serveur, elle reste disponible).
			expect(FreeCrateFlow.isCurrent(flow, session)).toBe(false)
			expect(flow.phase).toBe("idle")
			-- Une nouvelle ouverture au retour a sa propre séance.
			local again = FreeCrateFlow.start(flow)
			expect(again ~= session).toBe(true)
			expect(FreeCrateFlow.isCurrent(flow, session)).toBe(false)
			expect(FreeCrateFlow.isCurrent(flow, again)).toBe(true)
		end)

		it("demande sans réponse : la fenêtre se referme au bout du délai", function()
			local flow = FreeCrateFlow.new()
			FreeCrateFlow.start(flow)
			FreeCrateFlow.sent(flow, 100)
			expect(FreeCrateFlow.timedOut(flow, 103, 4)).toBe(false)
			expect(FreeCrateFlow.timedOut(flow, 104.5, 4)).toBe(true)
			FreeCrateFlow.shown(flow)
			expect(FreeCrateFlow.timedOut(flow, 200, 4)).toBe(false)
		end)

		it("pendant l'animation, jamais de délai dépassé (rien n'a été envoyé)", function()
			local flow = FreeCrateFlow.new()
			FreeCrateFlow.start(flow)
			expect(FreeCrateFlow.timedOut(flow, 1e6, 4)).toBe(false)
		end)
	end)
end
