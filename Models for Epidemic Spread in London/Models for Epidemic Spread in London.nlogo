extensions [gis csv]
; Defining breeds and agent variables
breed [boroughs borough]
breed [persons person]
globals [gem gem-line gem-list gem-namelist map-list borough-populations mortality]
patches-own [name n]

boroughs-own [population inf-num outbreak? respond? Epidemic-control]

persons-own [
  personstatus ; 0-susceptible, 1-latency 2-onset, -1-resist
  infected-time  ; ticks
]




; Procedure to setup the map using GIS extension
to setup-map
  set gem gis:load-dataset "London_Borough_Excluding_MHW.shp" ; Load the shapefile dataset
  gis:load-coordinate-system "London_Borough_Excluding_MHW.prj" ; Load the coordinate system from the projection file
  gis:set-world-envelope gis:envelope-of gem ; Set the world envelope to match the GIS data envelope
  let envelope gis:envelope-of gem ; Get the GIS data envelope
  set-patch-size 20 ; Set the visual size of each patch in the interface
  gis:apply-coverage gem "ONS_INNER" name ; Apply coverage to assign patch names based on the GIS attribute
  ask patches [
    if name = "F" [set pcolor brown + 2]
    if name = "T" [set pcolor brown + 2] ; If the patch name is "F" and "T", set the patch color to brown
  ]
end

; Main setup procedure
to setup
  clear-all
  reset-ticks ; Reset the tick counter
  set gem-line gis:load-dataset "London_line.shp" ; Load a line shapefile dataset
  set gem gis:load-dataset "London_Borough_Excluding_MHW.shp" ; Load the main shapefile dataset
  gis:set-world-envelope gis:envelope-of gem ; Set the world envelope to match the GIS data envelope
  let envelope gis:envelope-of gem ; Get the GIS data envelope
  set-patch-size 20 ; Set the visual size of each patch in the interface
  set gem-list gis:feature-list-of gem ; Create a list of GIS features from the dataset
  display-gem-line ; Procedure to display the GIS lines on the map
  ask patches [set pcolor white]
  init-boroughs ; Procedure to setup nodes (turtles) at GIS feature locations
  setup-network ; Procedure to setup network links between borough turtles
  ; Randomly selecting a certain number of cities as initial outbreak sites.
  ask n-of initial-outbreak-borough-num boroughs [
    become-infected
    if any? persons-here [  ; Check if there are persons on the borough patch
      ask one-of persons-here [
      set-personstatus 1
      ]
    ]
  ]
  ask links [set color violet + 1] ; Set the color of links


end

;Defining urban state change, defining viral transmission
to go
  ifelse all? boroughs [color = blue or color = gray] [
    stop
  ] [
    ; If not all turtles have outbreak, execute the following
    if all? boroughs [not outbreak?] [
      ask boroughs with [color != blue] [
        ; If the inf-num is less than or equal to zero, set its color to gray
        if inf-num <= 0 [
          set inf-num 0 set color gray                                                   ;All city dwellers have acquired antibodies, and the number of infections is zero.
        ]
        ; Choose a random subset of turtles with a positive inf-num and infect them
        let m random count boroughs with [inf-num > 0]
        ask n-of m boroughs with [inf-num > 0] [
          become-infected
        ]
      ]
    ]
  ]
  ask boroughs [
    set Epidemic-control Epidemic-control + 1
    if Epidemic-control >= Epidemic-control-frequency [
      set Epidemic-control 0
    ]
  ]
  inborough-spread
  borough-to-borough-spread
  interborough-travel
  update-borough-inf-num-and-status
  virus-detection
  ask boroughs  [
    if inf-num < 0 [
      set inf-num 0
      set color gray
    ]
  ]
  ask one-of boroughs [
  print (word "Infected number for borough " who ": " inf-num)
]
  display-labels
  tick
end

;Counting the number of infections in a city
to update-borough-inf-num-and-status
  ask boroughs [
    ; Calculate the number of persons in the city with personstatus 1 and 2
    let infected-persons count persons-here with [personstatus = 1 or personstatus = 2]
    set inf-num infected-persons
  ]
end

;Defining cities Model
;initial-outbreak-borough-num
to init-boroughs
  set borough-populations csv:from-file "POPULATION.csv"
  let l 0
  set gem-namelist [] ; Initialize an empty list to store feature properties
  repeat length gem-list [
    set gem-namelist lput gis:property-value item l gem-list "NAME" gem-namelist ; Add the "GN" property value to the list
    set l (l + 1)
  ]
  set-default-shape boroughs "circle" ; Set the default shape for turtles
  let i 0
  repeat length gem-list [
    let borough-name gis:property-value item i gem-list "NAME"
    let borough-population item 1 first filter [row -> first row = borough-name] borough-populations
    create-boroughs 1 [
      setxy      ;set label borough-name
        first gis:location-of gis:centroid-of gis:find-one-feature gem "NAME" item i gem-namelist ; Set x coordinate to the centroid of the feature
        last gis:location-of gis:centroid-of gis:find-one-feature gem "NAME" item i gem-namelist ; Set y coordinate to the centroid of the feature
      set color 9.9
; set the agent's population attributes
      set size ln (borough-population / 100000)
      ifelse is-string? borough-population [
        set population 0 ; If the corresponding population number cannot be found, it is set to 0
      ][
        set population borough-population
      ]
    ]
    set i (i + 1)
  ]
  foreach sort boroughs [ b ->
    ; Check if c is not nobody before calling init-residences
    if b != nobody [
      init-residences ([population] of b)  / numPersonPerTurtle b
   ]
  ]
  if any? boroughs [ ask boroughs [keep-susceptible] ] ; Make sure there are boroughs before asking them to become susceptible ; Procedure to make turtles susceptible to infection
end

; Procedure to setup network links between boroughs
to setup-network
  let j network-degree ; Define the degree of the network
  repeat j [
    ask boroughs [
      let choice up-to-n-of j min-n-of j other boroughs [distance myself] ; Choose up to j nearest boroughs
      if choice != nobody [create-links-with choice] ; Create links with chosen boroughs
    ]
  ]
end
; Initialisation of resident agents (person)
to init-residences [pop homeborough]
  ;every turtle represents 10,000 real people
  create-persons pop [
    hide-turtle                      ;Avoid messing up the graphical display of the simulation
    move-to homeborough                 ;homeborough: the borough where these human agents are located.
    set-personstatus 0
  ]
end

;The person spreading mechanism: it selects up to R0 (the basic number of infections) surrounding susceptible persons according to each infected person and infects them with a spread-rate probability.
to inborough-spread
  ask persons with [personstatus > 0][; For all individuals with a status greater than 0 (i.e. infected) do the following Select up to Basic-infections from the surrounding susceptible population (status 0)
    ask up-to-n-of Basic-infections (other persons-here) with [personstatus = 0][     ;Spread-rate decision to infect these susceptible individuals
      if random-float 1 < spread-rate [
        set-personstatus 1                                             ; Infect them, set the status to 1
      ]
    ]                                                            ; If the number of days of infection reaches the incubation period, the status is set to 2 (disease onset)
    if (infected-days >= latency-period)[set personstatus 2]

    ; recovery
    if (infected-days >= (latency-period + onset-period)) [          ; If the number of days of infection exceeds the incubation period plus the onset period, the recovery process is implemented
      ifelse (random-float 1 <= death-rate)
      [
        ; If number is less than or equal to the death rate,the person dies and the mortality is increased
        set mortality mortality + 1
        die
      ]
      [
        ;Randomly determines whether the individual recovers completely (status -1) or merely removes the symptom (status 0)
        set-personstatus ifelse-value (random-float 1 <= Resist-rate)[-1][0]
      ]
    ]
  ]
end

to borough-to-borough-spread
  ask boroughs with [outbreak? and not respond?] [
    let local-infected any? persons-here with [personstatus > 0]
    if local-infected [become-infected-transmitted]
    ; Check if there are neighboring boroughs before trying to infect them
    if any? link-neighbors [
      ask link-neighbors with [not respond?] [
        if local-infected [
          let susceptible-neighbors persons-here with [personstatus = 0]
          if any? susceptible-neighbors [
            ask susceptible-neighbors [
              if random-float 1 < spread-rate [
                set personstatus 1
                ; Ensure boroughs-here is not empty before calling become-infected-transmitted
                if any? boroughs-here [ ask one-of boroughs-here [become-infected-transmitted] ]
              ]
            ]
          ]
        ]
      ]
    ]
  ]
end

to interborough-travel
  if network-degree > 0 [
    ask n-of 100 persons [
      let des one-of [link-neighbors] of one-of boroughs-here
      if des != nobody [
        move-to des
          ask one-of boroughs-here [
          ; If there are any infected persons now in the borough, change its state
            if any? persons-here with [personstatus > 0] [
              become-infected-transmitted
          ]
        ]
      ]
    ]
  ]
end

;Personnel status
to set-personstatus [x]
  set personstatus x
  set-color-based-on-personstatus
  set infected-time ticks  ;Marks the time when the status change occurred.
end

to set-color-based-on-personstatus
  set color ifelse-value (personstatus = 0)[green][
    ifelse-value (personstatus = 1) [red][gray]
  ]
end

to-report infected-days           ;Count the number of days since an individual was infected.
  report ticks - infected-time    ;The time an individual is recorded as infected (infected-time)
end


;The five states of boroughs

to become-infected-transmitted ;Outbreaks caused by c via the Internet
  set outbreak? true
  set respond? true
  set color red ;
  ask my-links [
    set color red + 1]
    if lock? [
       ask my-links [die]
    ]
end


to keep-susceptible
  set outbreak? false
  set respond? false
  set color blue
  ask my-links
    [set color violet + 3]
end

to become-respond
  set outbreak? false
  set respond? true
  set color brown
  ask my-links
    [set color turquoise + 2]
end

to become-lurking
  set outbreak? false
  set respond? false
  set color green
  ask my-links
    [set color violet + 3]
end

to become-infected
  set outbreak? true
  set respond? true
  set color red
end

to virus-detection
  ask boroughs with [outbreak? and Epidemic-control = 0]
  [if random 100 < testing-chance
    [ifelse inf-num < outbreak-end
      [become-respond]
      [become-lurking]]]
end


; Procedure to display labels on boroughs
to display-labels
  ask boroughs [set label ""] ;
  if show-inf-num? [ ; If the global variable show-inf-num? is true
    ask boroughs [set label inf-num] ; Set the label of each borough to its inf-num variable
  ]
end

; Procedure to display the GIS lines on the map
to display-gem-line
  gis:set-drawing-color 0
  gis:draw gem-line 1.5 ; Draw the GIS line with a width of 1
end
@#$#@#$#@
GRAPHICS-WINDOW
544
10
1212
679
-1
-1
20.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

SWITCH
273
464
376
497
lock?
lock?
0
1
-1000

BUTTON
457
424
533
457
NIL
setup-map
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
19
505
364
538
initial-outbreak-borough-num
initial-outbreak-borough-num
0
10
3.0
1
1
NIL
HORIZONTAL

BUTTON
274
423
348
456
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
20
462
257
495
network-degree
network-degree
0
10
3.0
1
1
NIL
HORIZONTAL

INPUTBOX
375
524
534
584
numPersonPerTurtle
10000.0
1
0
Number

PLOT
22
10
530
151
population
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"latency" 1.0 0 -955883 true "" "plot count persons with [personstatus = 1]"
"mortality" 1.0 0 -16777216 true "" "plot mortality"
"onset" 1.0 0 -5298144 true "" "plot count persons with [personstatus = 2]"
"resist" 1.0 0 -7500403 true "" "plot count persons with [personstatus = -1]"

SLIDER
18
590
192
623
Basic-infections
Basic-infections
0
10
6.0
0.1
1
NIL
HORIZONTAL

SLIDER
202
590
363
623
spread-rate
spread-rate
0
1
0.95
0.01
1
NIL
HORIZONTAL

SLIDER
374
631
536
664
latency-period
latency-period
0
100
14.0
1
1
NIL
HORIZONTAL

SLIDER
18
629
192
662
onset-period
onset-period
0
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
202
629
364
662
death-rate
death-rate
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
374
591
534
624
Resist-rate
Resist-rate
0
1
0.5
0.01
1
NIL
HORIZONTAL

BUTTON
364
424
438
457
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
385
464
533
497
show-inf-num?
show-inf-num?
0
1
-1000

SLIDER
20
424
257
457
Epidemic-control-frequency
Epidemic-control-frequency
0
100
3.0
1
1
ticks
HORIZONTAL

SLIDER
201
550
366
583
testing-chance
testing-chance
0
100
50.0
0.1
1
%
HORIZONTAL

SLIDER
19
548
191
581
outbreak-end
outbreak-end
0
500
3.0
1
1
NIL
HORIZONTAL

PLOT
22
299
534
419
Status
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"respond" 1.0 0 -8431303 true "" "plot count boroughs with [color = brown or color = red]"
"controlled" 1.0 0 -1069655 true "" "plot count boroughs with [color = red]"
"normal" 1.0 0 -7500403 true "" "plot count boroughs with [color = gray]"
"lurking" 1.0 0 -8330359 true "" "plot count boroughs with [color = green]"
"unaffected" 1.0 0 -10649926 true "" "plot count boroughs with [color = blue]"

PLOT
22
158
533
292
Inf-num
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Infected" 1.0 0 -16777216 true "" "plot sum [inf-num] of boroughs"

@#$#@#$#@
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
