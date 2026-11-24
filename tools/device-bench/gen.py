# Generates the bench corpus: 5 trap categories x 200 + 100 general dictations, with gold labels.
# Seeded (42): the same cases.json every run. Writes cases.json in the current directory.
import random, json
R = random.Random(42)
P = ["Tom","Léa","Marc","Julie","Sophie","Karim","Inès","Hugo","Camille","Nadia","Paul","Emma","Lucas","Chloé","Mehdi","Sarah","Antoine","Manon","Yanis","Clara"]
CUE = ["non pardon","enfin non","ah non","en fait non","non attends","ou plutôt","je veux dire","euh non","non je me suis trompé","pardon"]
DAYS=["lundi","mardi","mercredi","jeudi","vendredi","samedi","dimanche"]
PLACES=["la gare","la mairie","le cinéma","la boulangerie","le bureau","la pharmacie","le parc","la piscine","le resto","la médiathèque"]
OBJ=["le dossier","la facture","les photos","le devis","le contrat","les clés","le rapport","la présentation","le planning","les billets"]
FOOD=["du pain","du lait","des œufs","du fromage","des pommes","du café","de la farine","des pâtes","du riz","des tomates"]
CITIES=["Lyon","Marseille","Lille","Nantes","Bordeaux","Toulouse","Rennes","Nice","Grenoble","Strasbourg"]
def pick(l, k=1): return R.sample(l, k) if k>1 else R.choice(l)
cases=[]
def add(cat, text, **gold): cases.append(dict(cat=cat, text=text, **gold))

# A — spoken self-corrections (the clean gate must never skip them)
seen=set()
while sum(c['cat']=='A' for c in cases)<200:
    cue=pick(CUE); t=R.randrange(6)
    if t==0: a,b=pick(DAYS,2); s=f"on se voit {a} {cue} {b} devant {pick(PLACES)}"
    elif t==1: a,b=pick(PLACES,2); s=f"je t'attends devant {a} {cue} devant {b}"
    elif t==2: a,b=pick(P,2); s=f"tu peux envoyer {pick(OBJ)} à {a} {cue} à {b} avant ce soir"
    elif t==3: a,b=pick(OBJ,2); s=f"j'ai oublié {a} {cue} {b} au bureau"
    elif t==4: a,b=pick(CITIES,2); s=f"il part vivre à {a} {cue} à {b} en septembre"
    else: a,b=pick(DAYS,2); s=f"la réunion est {a} matin {cue} {b} matin"
    if s in seen: continue
    seen.add(s); add('A', s[0].upper()+s[1:], wrong=a, right=b)

# B — announcements that call for ":"
seen=set()
B=[lambda: (f"j'ai croisé {pick(P)} il m'a dit un truc de fou il {R.choice(['sort avec','a quitté','va épouser'])} {pick(P)}"),
   lambda: (f"devine quoi {R.choice(['j ai eu le poste','on part à '+pick(CITIES),'le contrat est signé','ma sœur est enceinte'])}".replace('j ai',"j'ai")),
   lambda: (f"j'ai une {R.choice(['bonne','mauvaise','grosse'])} nouvelle {R.choice(['on déménage à '+pick(CITIES),'le vol est annulé','la réunion saute','on a gagné le match'])}"),
   lambda: (f"voilà ce qu'on va faire {R.choice(['tu prends la voiture et je prends le train','tu appelles '+pick(P)+' et je gère le reste','on part tôt et on mange là-bas'])}"),
   lambda: (f"il faut acheter trois choses {', '.join(pick(FOOD,2))} et {pick(FOOD)}"),
   lambda: (f"tu sais ce qu'il m'a répondu {R.choice(['il s en fichait','il avait oublié','il était déjà parti'])}".replace("s en","s'en")),
   lambda: (f"la réponse est simple {R.choice(['on n a pas le budget','personne n est dispo','c est trop tard'])}".replace("n a","n'a").replace("n est","n'est").replace("c est","c'est")),
   lambda: (f"petit rappel {R.choice(['la réunion est déplacée à '+pick(DAYS),'les clés sont chez '+pick(P),'on ferme à midi '+pick(DAYS)])}"),
   lambda: (f"{pick(P)} m'a annoncé une grande nouvelle {R.choice(['elle déménage à','il part vivre à'])} {pick(CITIES)}"),
   lambda: (f"il nous manque deux trucs {pick(FOOD)} et {pick(FOOD)}"),
]
while sum(c['cat']=='B' for c in cases)<200:
    s=R.choice(B)()
    if s in seen: continue
    seen.add(s); add('B', s[0].upper()+s[1:])

# C — controls: same words, no announcement, no ":" expected
seen=set()
C=[lambda: f"j'ai croisé {pick(P)} et il m'a dit qu'il passerait {pick(DAYS)}",
   lambda: f"il m'a dit qu'il viendrait {pick(DAYS)} matin",
   lambda: f"j'ai acheté {pick(FOOD)} et {pick(FOOD)} en rentrant",
   lambda: f"le problème est réglé depuis {pick(DAYS)}",
   lambda: f"{pick(P)} a trouvé une nouvelle voiture à {pick(CITIES)}",
   lambda: f"on se retrouve devant {pick(PLACES)} après le travail",
   lambda: f"la réunion de {pick(DAYS)} est simple à préparer",
   lambda: f"tu sais qu'il part à {pick(CITIES)} la semaine prochaine",
   lambda: f"je te rappelle quand j'arrive à {pick(PLACES)}",
   lambda: f"il faut que je passe chercher {pick(OBJ)} chez {pick(P)}",
]
while sum(c['cat']=='C' for c in cases)<200:
    s=R.choice(C)()
    if s in seen: continue
    seen.add(s); add('C', s[0].upper()+s[1:])

# D — dictated emails: greeting + body + sign-off (+ signature)
GREET_F=["Bonjour {n}","Bonjour à tous","Bonsoir {n}","Bonjour madame {n}","Bonjour monsieur {n}","Cher {n}"]
BODY=["je te confirme notre rendez-vous de {d} à {p}","je vous écris au sujet de {o} du mois dernier","suite à notre échange je t'envoie {o} en pièce jointe",
      "petit rappel la réunion d'équipe est déplacée à {d} matin","je reviens vers vous concernant {o}","merci pour ton retour sur {o}",
      "je serai absent {d} et {d2}","pourriez-vous me renvoyer {o} corrigé","par ailleurs j'ai besoin de ta validation avant {d}","n'hésite pas si tu as des questions"]
CLOSE_F=["cordialement","bien cordialement","bonne journée","bonne soirée","à bientôt","bien à vous","merci d'avance cordialement","belle journée"]
seen=set()
while sum(c['cat']=='D' for c in cases)<200:
    g=R.choice(GREET_F).format(n=pick(P)); nb=R.choice([1,2,2,3])
    body=" ".join(b.format(d=pick(DAYS),d2=pick(DAYS),p=pick(PLACES),o=pick(OBJ)) for b in R.sample(BODY,nb))
    cl=R.choice(CLOSE_F); sig=R.choice(["", pick(P), pick(P)+" "+R.choice(["Martin","Durand","Bernard","Petit","Moreau"])])
    s=f"{g} {body} {cl} {sig}".strip()
    if s in seen: continue
    seen.add(s); add('D', s, greeting=g, closing=cl, signature=sig)

# E — text messages and fake emails: must stay on one line
E=[lambda: f"Salut {pick(P)} merci pour ton message je regarde ça ce soir bisous",
   lambda: f"Coucou {pick(P)} tu viens {pick(DAYS)} soir bises",
   lambda: f"Salut {pick(P)} on se voit à {pick(PLACES)} à plus",
   lambda: f"Il m'a répondu cordialement mais il n'a pas envoyé {pick(OBJ)}",
   lambda: f"Elle a dit bonjour à {pick(P)} et elle est repartie à {pick(PLACES)}",
   lambda: f"J'ai reçu un mail de {pick(P)} pour {pick(OBJ)} il faut répondre avant {pick(DAYS)}",
   lambda: f"Bonjour je voulais savoir si {pick(OBJ)} était prêt",
   lambda: f"Je te confirme {pick(DAYS)} cordialement",
   lambda: f"Tu peux écrire bonjour madame au début du mail pour {pick(P)}",
   lambda: f"Bonne journée à toi aussi {pick(P)}",
]
seen=set()
while sum(c['cat']=='E' for c in cases)<200:
    s=R.choice(E)()
    if s in seen: continue
    seen.add(s); add('E', s)

# G — 100 general dictations, everyday register
G=[f"je serai un peu en retard ce soir commence sans moi",f"est-ce que tu peux passer prendre {{f}} en rentrant",f"on mange chez {{n}} {{d}} soir tu viens",
   f"j'ai laissé {{o}} sur ton bureau",f"rappelle-moi quand tu sors de ta réunion",f"le train pour {{c}} a vingt minutes de retard",
   f"tu as pensé à réserver pour {{d}}",f"je pars de {{p}} dans dix minutes",f"merci pour hier soir c'était super",f"il pleut à {{c}} prends un parapluie",
   f"j'ai rendez-vous chez le dentiste {{d}} à onze heures",f"on peut décaler notre appel à demain",f"{{n}} arrive à quatorze heures trente",
   f"je t'envoie {{o}} dès que je l'ai",f"tu veux qu'on aille courir {{d}} matin"]
seen=set()
while sum(c['cat']=='G' for c in cases)<100:
    s=R.choice(G).format(f=pick(FOOD),n=pick(P),d=pick(DAYS),o=pick(OBJ),c=pick(CITIES),p=pick(PLACES))
    if s in seen: continue
    seen.add(s); add('G', s[0].upper()+s[1:])

VOICES=["Thomas (Français (France))","Jacques","Eddy (Français (France))","Flo (Français (France))","Sandy (Français (France))",
        "Shelley (Français (France))","Rocko (Français (France))","Grandma (Français (France))","Grandpa (Français (France))","Amélie"]
for i,c in enumerate(cases):
    c['id']=f"{c['cat']}{i:04d}"
    c['voice']=VOICES[i%len(VOICES)]
    c['rate']=R.choice([150,175,195,215,235])
    c['noise']=R.choice([0,0,0.01,0.03])
json.dump(cases,open('cases.json','w'),ensure_ascii=False,indent=1)
from collections import Counter; print(Counter(c['cat'] for c in cases))
for cat in "ABCDEG": print([c['text'] for c in cases if c['cat']==cat][:2])
