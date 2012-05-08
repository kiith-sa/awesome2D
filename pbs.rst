
* Autor: Ferdinand Majerech
* Vedúci: Ladislav Mikeš

2D grafika
----------------------

.. image:: dopefish.gif
   :align: center

2D grafika
----------------------

+/-
^^^^^^

* Nízka baréra vstupu pre programátorov aj pre umelcov
  (indie komunita, modderi)

* Nízke hardwarové nároky 
  (Nevýznamné pri AAA hrách, niekedy významné pri konzolách,
  významné pri webových, mobilných hrách)
 
* Vhodné pre určíté žánre (RTS, RPG...)

* Niekedy vysoké nároky na grafikov (kreslenie spritov z viacerých strán)

Predrenderovaná 2D grafika 
--------------------------

* Zjednodušuje prácu grafikom

* Stačí jeden model a program ktorý vypľuje všetky sprity

* V 3D produkcii sa netreba starať o optimálnosť modelu,
  nie je nutné UV-mapovať, atď.

* Na čase predrenderovania nezáleží, dá sa použiť raytracing,
  radiosity - omnoho lepší obraz ako pri real-time rasterizácii

Osvetlenie v 2D
---------------

* Zvyčajne nie sú údaje o orientácii povrchov (napr. normály)

* Dynamické osvetlenie len ak veľmi obmedzené

Osvetlenie v 2D
---------------

* Rovnomerné osvetlenie v kruhu od svetelného zdroja

  .. image:: circle_lighting.jpg
     :align: center
     :width: 6cm

Osvetlenie v 2D
---------------

* Statické predrenderované/predkreslené osvetlenie

  .. image:: prerendered_lighting.jpg
     :align: center
     :width: 6cm

Osvetlenie v 2D
---------------

* V špecálnych prípadoch lepšie, dynamické 
  osvetlenie, ale nie všeobecne

  .. image:: topdown_shadows.jpg
     :align: center
     :width: 6cm

Môj prístup
-----------

* Dnes máme programovateľné GPU

* Cez fragment shadery (napr. v GLSL) sa dajú predrenderovať normály 
  a iné dáta z 3D modelu

* V 2D sa difúzna a normálova mapa pre jeden sprite
  dá použiť na 3D osvetlenie (fragment shader, alebo priamo
  na CPU)

* To je len začiatok


Techniky
--------

* "Uhlové mapy": RGB  + mapa 2D uhlov

* "2-uhlové mapy": RGB + mapa polárnych koordinátov (iné zakódovanie normálovej mapy)

* Normálové mapy: Hlavný cieľ práce

* Mapy 3D koordinátov 
  
  - V kombinácii s normálovou mapou
    úplne 3D osvetlenie namiesto 2D osvetlenia na výsledku 
    napr. izometrickej projekcie


Techniky
--------

* Mapy podľa bázových vektorov
  inšpirované osvetlením v Source engine od Valve
  (napr. Half-Life 2)

  - Svetelné mapy zo 6 strán kocky (stačí 5?)

  - Normálový vektor sa rozdelí na zložky podľa štandardnej bázy.
    Aplikuje sa osvetlenie z máp podľa dĺžky a znamienka zložiek.

  - Dajú sa aj iné bázy a menej máp (3).

  - Výsledok: self-shadowing

Techniky
--------

* Normálová mapa

  .. image:: normal_lighting.png
     :align: center
     :width: 9cm

Techniky
--------

* Mapy podľa bázových vektorov

  .. image:: basis_lighting.png
     :align: center
     :width: 9cm

Techniky
--------

* Spekulárne mapy?

* Tiene? (hacky)

Implementácia
---------------------

* Engine: D, OpenGL, GLSL
* Backend utilita na predrenderovanie: D

  - CLI
  - Použiteľná cez skripty
  - PNG výstup
  - OpenGL/GLSL na predrenderovanie
  - Možno: Yafaray || Cycles || LuxRender na predrenderovanie

* GUI frontend: D/DGameUI || C++/Qt || Python/Qt || Vala/Gtk ...

Ciele
-----

* Hlavný cieľ: 
  
  - Osvetlenie pomocou normálových máp v 2D
  - Vytvorenie open source nástroja na predrenderovanie 3D-to-2D

* Hlavný vedľajší cieľ: Napísať bakalárku

* Vedľajší vedľajśi cieľ: Porovnanie viacerých techník

  - Obraz
  - Pamäťové nároky
  - Výpočtové nároky
  - Produkčné nároky

.. header::

        Pokročilé osvetlenie v 2D grafike

.. footer::

        © Ferdinand Majerech, 2012
