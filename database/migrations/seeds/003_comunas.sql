UPDATE beneficiario
SET comuna = (ARRAY['Popular','Manrique','Aranjuez','Robledo',
                    'Laureles-Estadio','Belén','La América','Villa Hermosa'])
             [1 + (id_beneficiario % 8)]
WHERE comuna IS NULL;