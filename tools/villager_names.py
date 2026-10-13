#!/usr/bin/env python3
"""A FEW THOUSAND NAMES FOR VILLAGERS, and the checks that keep them honest.

Every villager was named from twelve names a sex, so every town in the world was
full of Pips and Lomaxes. The names are here now, grouped by the tradition they
come from, and written to data/villager_names.json, which the game reads
(scripts/villager/villager_names.gd). A town never gives out a name it has
already given, so with this many two neighbouring towns share hardly any.

ADD A NAME by putting it in the right list below and running

    python3 tools/villager_names.py --write

Run bare (as the suite does) to check that:
  - the shipped file is exactly what these lists make;
  - there are at least MIN_EACH names for each sex, none repeated;
  - every name is plain letters, capitalised, short enough for the label over
    a villager's head, and on no list of names this game will not use;
  - the game reads the file, names every villager through VillagerNames, and
    hands nobody a name their town has already given, newborn or brought back
    from a save (a town saved with repeats loses them as it loads);
  - every export ships *.json, so the file goes out with the game.

Written in ASCII, without accents, so every label font draws them.
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "data/villager_names.json"
MIN_EACH = 1500
LONGEST = 12
SHAPE = re.compile(r"^[A-Z][a-z]+$")
# Names of tyrants and of gods people still pray to, and words a reader would
# take for something else. A villager can be eaten by a monster in this game.
NEVER = {
    "Adolf", "Allah", "Benito", "Caligula", "Durga", "Herod", "Hitler", "Indra",
    "Isis", "Jesus", "Judas", "Krishna", "Lakshmi", "Lucifer", "Mohammed",
    "Muhammad", "Nero", "Osama", "Parvati", "Satan", "Shiva", "Stalin", "Usama",
    "Dick", "Dong", "Fanny", "Gay", "Hore", "Wang",
}

FEMALE = {
    "english": """
        Ada Adela Adelaide Agatha Agnes Alice Alison Alys Amabel Amice Amy Annabel
        Annis Anstice Arabella Audrey Avelina Avice Barbary Beatrix Bel Bella Bess
        Bertha Bettris Blanche Bridget Cassandra Cecily Christabel Cicely Clarice
        Clemence Constance Damaris Denise Dina Dorcas Dorothy Dowsabel Dulcie Edith
        Edwina Elaine Eleanor Ellen Elsie Elspeth Emmeline Emmot Ermengarde Esther
        Ethel Eustacia Eve Felice Florence Fortune Frideswide Gillian Gillot Godiva
        Grace Grisel Gwendolen Hawise Helewise Hester Hilda Honor Isabel Isolde Ivy
        Jacquetta Jennet Jessamy Joan Jocosa Joyce Juliana Juliet Katherine Kateryn
        Laura Letitia Lettice Lucinda Lucy Mabel Magdalen Margaret Margery Marigold
        Marion Marjory Martha Mary Matilda Maud Maudlin Mercy Meriel Mildred
        Millicent Mirabel Muriel Nan Nell Nesta Nicola Olive Opal Orabel Parnel
        Patience Pernel Petronel Philippa Phoebe Primrose Prudence Rohesia Rosa
        Rosalind Rosamund Rose Sabina Selina Sibyl Sophia Susanna Tabitha Tamsin
        Temperance Theodora Thomasin Tiffany Tilda Ursula Wilmot Winifred
    """,
    "old english": """
        Aebbe Aelfgifu Aelflaed Aelfrun Aelfthryth Aelfwaru Aelfwynn Aethelflaed
        Bebba Brihtgifu Cyneburh Cynethryth Eadburh Eadgifu Eadgyth Ealdgyth
        Eanflaed Ealhswith Ecgwynn Edburga Ethelburga Frithuswith Godgifu Godwaru
        Hereswith Hild Hildelith Leofgifu Leofrun Mildburh Mildthryth Osgyth
        Osthryth Tette Waerburh Wihtburh Wulfgifu Wulfrun Wulfwaru Wynflaed
    """,
    "irish and scots": """
        Ailbhe Aideen Aine Aisling Aoife Bebinn Blathnat Breda Brigid Caoimhe
        Cliodhna Clodagh Dearbhla Deirdre Dervla Doireann Eimear Eithne Emer Etain
        Ethna Fand Fionnuala Gormlaith Grainne Ide Maeve Muireann Muirne Niamh
        Nuala Orla Orlaith Roisin Sadhbh Saoirse Sinead Siobhan Sorcha Una
        Ailsa Beathag Catriona Eilidh Iseabail Ishbel Isla Kirsty Mairi Marsaili
        Morag Peigi Raonaid Seonag Shona Sileas
    """,
    "welsh breton cornish": """
        Angharad Arianwen Awen Bethan Blodwen Branwen Buddug Carys Catrin Ceridwen
        Cerys Delyth Dilys Eira Elen Eluned Enid Ffion Gwen Gwenda Gwenllian
        Gwyneth Heledd Llinos Lowri Mair Megan Mererid Morwenna Nerys Nia Olwen
        Rhian Rhiannon Seren Sian Tangwen Tegan Tegwen
        Anaig Aziliz Azenor Enora Gwenaelle Gwenola Katell Maiwenn Nolwenn Rozenn
        Soazig Bryluen Demelza Ebrel Elowen Jenna Kerensa Lamorna Lowena Morvoren
        Senara Tressa Wenna
    """,
    "norse": """
        Aase Agnete Agneta Alfdis Alfhild Alva Asa Asgerd Aslaug Asta Astrid Asvor
        Aud Bera Bergljot Birgit Bodil Borghild Brita Brynhild Dagmar Dagny Dalla
        Ebba Eir Elin Elsa Embla Estrid Freya Freydis Frida Geirny Gerd Greta Groa
        Gudlaug Gudny Gudrun Gunborg Gunhild Gunnvor Gyda Gyrid Halla Hallgerd
        Hallveig Hedda Helga Helle Herdis Hervor Hillevi Hjordis Hlif Hrefna Inga
        Inge Ingeborg Ingela Ingibjorg Ingrid Ingunn Jofrid Jorunn Kari Karin
        Kerstin Kirsten Lene Linnea Liv Lovisa Malin Mette Oddny Osk Ragna
        Ragnfrid Ragnhild Ragnvor Rannveig Runa Saeunn Saga Sanna Sigfrid Signe
        Signy Sigrid Sigrun Siv Solveig Steinunn Sunniva Svanhild Thora Thordis
        Thorgerd Thorhild Thorunn Thyra Tilde Torhild Tove Trine Turid Tyra
        Ulfhild Ulla Unn Valdis Vibeke Vigdis Ylva Yrsa
    """,
    "german and frankish": """
        Adalheid Adelgund Adelheid Adelinde Alruna Amalberga Amalia Berta Bertrada
        Brunhild Brunhilde Clotilde Cunigunde Edeltraud Elfriede Emma Ermelinde
        Ermentrude Fastrada Fridrun Friedrun Gerberga Gerlinde Gertrud Gisela
        Gretel Gudula Gunda Gundrada Hadmut Hadwig Hanne Hedwig Heidrun Heilwig
        Hemma Hertha Hildburg Hildegard Hiltrud Hrotsvit Ida Ilse Imma Irmgard
        Irmina Irmtraud Kriemhild Kunigunde Liesel Liutgard Lotte Mathilde
        Mechthild Minna Notburga Oda Odile Ottilie Radegund Reinhild Richenza
        Rosamunde Roswitha Sieglinde Swanhild Theda Theodelinde Trudel Trudi Uta
        Ute Walburga Waldrada Waltraud Wendelgard Wiborada Wilhelmine Wiltrud
    """,
    "french": """
        Aalis Adele Adeline Aelis Aelith Agathe Albane Alienor Aliette Amandine
        Angeline Annick Apolline Ariane Aude Aurore Belle Berenice Bertille
        Blancheflor Brigitte Capucine Cecile Celestine Charlotte Clarisse
        Clementine Colette Coralie Delphine Doucette Edwige Eliane Elodie Emeline
        Esclarmonde Ermessende Estelle Eugenie Fabienne Fanchon Faustine Fleur
        Fleurette Flore Gaelle Genevieve Germaine Ghislaine Gisele Guillemette
        Heloise Honorine Hortense Isaure Jacquette Jeanne Jehanne Josephine
        Josiane Laure Leontine Liliane Lisette Lucienne Lucile Madeleine Maelle
        Mahaut Manon Marceline Marcelle Margot Marguerite Mathurine Melisende
        Mireille Nicolette Ninon Noemie Odette Ombeline Oriane Pauline Perrette
        Petronille Philomene Reine Rosalie Roseline Sabine Sancie Seraphine
        Sidonie Solene Sylvie Toinette Valentine Violette Viviane Yolande Ysabeau
        Ysolde Zelie
    """,
    "roman and italian": """
        Aelia Aemilia Agrippina Albina Antonia Antonina Aurelia Calpurnia Camilla
        Cassia Cecilia Claudia Cornelia Domitia Drusilla Fabia Faustina Flavia
        Fulvia Galla Hortensia Julia Junia Livia Lucilla Lucretia Marcella
        Octavia Ottilia Paulina Placidia Porcia Prisca Priscilla Rufina Septimia
        Servilia Severa Silvia Tertia Tullia Urbana Valeria Valentina Vibia
        Vipsania Vitalia
        Agnese Alessandra Ambra Annunziata Assunta Beatrice Benedetta Bianca
        Brunella Carlotta Carmela Caterina Chiara Clelia Concetta Costanza
        Donatella Elettra Elisabetta Fiammetta Filomena Fiora Francesca Gaia Gemma
        Gilda Ginevra Giovanna Giulietta Graziella Ilaria Iolanda Isotta Laudomia
        Lavinia Letizia Lia Loretta Lucrezia Ludovica Maddalena Margherita Marta
        Matilde Mirella Nerina Nives Nunzia Olimpia Ornella Orsola Ottavia Paola
        Perla Pia Rachele Raffaella Renata Ricciarda Rina Rita Romilda Rosalba
        Selvaggia Serafina Simonetta Stella Sveva Tecla Teodora Tiziana Tosca
        Vanna Violante Virginia Vittoria Zita
    """,
    "greek": """
        Agape Aglaia Alcmene Alexandra Anastasia Anthea Antigone Arete Ariadne
        Artemisia Aspasia Athanasia Berenike Callista Calliope Charis Chloe
        Chrysanthe Chryseis Cleo Corinna Danae Daphne Delia Demetra Despina Dione
        Doris Dorothea Eirene Electra Eleftheria Eleni Elpis Erato Eudocia Eugenia
        Euphemia Eurydice Euterpe Evadne Evangelia Fotini Galatea Glykeria
        Harmonia Hecuba Helena Hermione Hero Hypatia Ianthe Ione Iphigenia Iris
        Ismene Kassandra Katerina Kyriaki Leda Lydia Lysandra Marina Melaina
        Melissa Melpomene Myrrine Nausicaa Nephele Nike Niobe Olympia Pandora
        Paraskevi Penelope Persephone Phaedra Pherenike Philomela Phyllis Rhea
        Rhoda Sappho Selene Sophronia Sotiria Stavroula Thais Thalia Theano Thekla
        Theodosia Theophano Urania Vasiliki Xanthe Xenia Zenobia Zinovia Zoe
    """,
    "hebrew": """
        Abigail Adah Atarah Avigail Ayelet Batya Bilhah Bracha Chava Chaya Dalit
        Deborah Dinah Dvora Edna Efrat Elisheva Galit Gila Hadas Hadassah Hannah
        Hila Ilana Jael Jemima Jochebed Judith Keturah Keziah Leah Leora Liora
        Mahlah Malka Meira Merav Michal Milcah Miriam Naamah Naomi Nava Neta Noa
        Ofra Orli Orpah Peninnah Rachel Rebekah Rivka Ruth Sarai Sarah Shiphrah
        Shira Shulamit Sigal Sima Talia Tamar Tikva Tirzah Tova Tzila Varda Yael
        Yaffa Yehudit Zehava Zillah Zilpah Zipporah
    """,
    "slavic": """
        Agata Agnieszka Alenka Alina Ania Anya Barbara Beata Bogdana Bogna Bogumila
        Bojana Bozena Branka Celina Danica Danuta Darina Dasha Desa Dobrava
        Dorota Dragana Dubravka Dunja Dusana Elzbieta Ewa Felicja Galina Genowefa
        Gorana Gordana Grazyna Halina Hana Hanna Inna Irena Irina Ivana Iwona
        Jadwiga Jagoda Jarmila Jasna Jelena Jolanta Kalina Kamila Kasia Katya
        Krystyna Ksenia Lada Larisa Lidka Ljuba Lubica Lucija Lucyna Ludmila
        Lybed Lyuba Magda Marfa Marianna Marija Marzena Masha Mila Milena Militsa
        Mira Miroslava Mojca Nada Nadezhda Nadia Nastya Natalya Natasa Neda Nevena
        Oksana Olena Olga Olja Petra Polina Predslava Rada Radka Radmila Ranka
        Rogneda Ruza Sanja Slavica Slavka Smiljana Snezana Sonya Stana Svetla
        Svetlana Tamara Tanja Tatiana Tihana Tijana Urszula Valya Vanja Varvara
        Vera Vesna Vida Vlasta Wanda Weronika Wioletta Yaroslava Yaroslavna Yelena
        Yeva Zabava Zdenka Zhanna Zlata Zofia Zora Zorica Zoya Zrinka Zuzana
        Zuzanna Zvezdana
    """,
    "baltic": """
        Agne Agrita Aija Aiste Antra Austeja Baiba Birute Dace Daina Dzintra Egle
        Gabija Gintare Ieva Ilona Ilze Indre Inese Jurate Kotryna Laima Lauma
        Liga Lina Maija Mara Milda Rasa Rasma Rimante Ruta Sarmite Saule Sigita
        Skaidrite Skaiste Vaiva Velta Vilte Zaiga Zane Zivile
    """,
    "finnish and estonian": """
        Aili Ainikki Aino Annikki Aune Eeva Elina Elle Ene Hellevi Helju Helmi
        Hilja Iiris Ilma Inkeri Irja Kaarina Kadri Kai Kaija Kaisa Katri Kerttu
        Kersti Kielo Kyllikki Lahja Laina Leida Lempi Liisa Lumi Lyyli Maie Mari
        Marjatta Martta Mielikki Neea Oili Orvokki Outi Pihla Pille Pirjo Rauha
        Reet Riitta Ronja Saara Saimi Sanni Selma Senja Siiri Sini Suoma Sunna
        Taimi Taina Tellervo Tiiu Toini Tuuli Tyyne Urve Vappu Venla Vieno Viivi
        Vuokko
    """,
    "hungarian": """
        Agota Aniko Aranka Boglarka Borbala Csilla Dorottya Edit Emese Eniko
        Erzsebet Eszter Etelka Gizella Gyongyi Hajnal Hedvig Ibolya Ildiko Irma
        Jolan Judit Kata Katalin Kincso Klara Lilla Magdolna Margit Melinda
        Orsolya Panna Piroska Reka Rozalia Rozsa Szilvia Timea Tunde Veronika
        Zsofia Zsuzsa
    """,
    "basque": """
        Ainhoa Alaia Amaia Ane Arantxa Edurne Garazi Haizea Idoia Irati Itziar
        Izaro Josune Leire Maialen Maite Miren Nahia Naroa Nekane Oihana Olatz
        Saioa Uxue Zurine
    """,
    "spanish and portuguese": """
        Adelaida Adosinda Alba Aldonza Almudena Amparo Ana Aurora Beatriz Begona
        Berenguela Blanca Branca Brianda Brites Carmen Catalina Clara Consuelo
        Constanza Dolores Dulce Elena Elvira Esperanza Estefania Eulalia Fernanda
        Filipa Florinda Gadea Graca Gracia Graciela Guadalupe Guiomar Ines
        Isabela Jimena Joana Juana Leocadia Leonor Lorena Lucia Luz Macarena
        Mafalda Manuela Marcela Maribel Marisol Mencia Mercedes Milagros
        Montserrat Nuria Oria Paloma Paz Pilar Remedios Rocio Rosalia Rosario
        Sancha Socorro Sol Soledad Teresa Toda Urraca Ximena Yolanda Ysabel
    """,
    "persian": """
        Anahita Arezoo Atoosa Azadeh Bahareh Banu Behnaz Darya Dorsa Elaheh Farah
        Faranak Farideh Fereshteh Gelareh Golnar Gordafarid Haleh Homa Katayoun
        Kiana Laleh Mahin Mahsa Mahtab Mandana Manijeh Marjan Mehrnaz Minoo Mitra
        Nahid Nasrin Nazanin Niloufar Pari Parisa Parvaneh Pegah Roshan Roxana
        Rudaba Sahar Setareh Shabnam Shahrzad Sheida Shirin Simin Soraya Sudabeh
        Tahmineh Taraneh Yalda Yasaman Zhaleh Ziba Zohreh
    """,
    "arabic": """
        Abla Afaf Aisha Alia Amal Amina Amira Arwa Asiya Asma Basma Bushra Dalal
        Dima Dunya Fadia Farida Fatima Ghada Ghalia Hadeel Hala Halima Hanan Hayat
        Hessa Hiba Hind Huda Ibtisam Inas Jamila Jumana Karima Khadija Khawla
        Laila Lamia Lubna Maha Majida Malak Marwa Maryam Mayada Mona Nabila Nadira
        Najat Najwa Nawal Nisreen Noor Nura Rabia Rahma Randa Rania Rasha Reem
        Rima Ruba Ruqayya Sabah Safiya Sakina Salma Samira Sana Sawsan Shatha Suha
        Thuraya Wafa Wardah Widad Yasmin Yusra Zahra Zainab Zakiya Zubaida
    """,
    "turkish and steppe": """
        Ainur Aigerim Aizhan Akmaral Altynai Aruzhan Asel Asli Aydana Ayla Aylin
        Ayse Aysel Bahar Bibigul Ceren Damla Dana Defne Derya Dilara Dinara Duygu
        Ebru Elif Esin Esra Feride Filiz Gamze Gul Gulmira Gulnar Gulnara Gulsen
        Hande Hulya Ilkay Indira Irmak Leyla Madina Melek Meltem Mine Nazira Nazli
        Nesrin Nilufer Oya Pinar Saltanat Selin Serap Sevda Sevgi Sibel Songul
        Togzhan Tugba Tulay Yasemin Yildiz Zehra Zeynep Zhibek
    """,
    "armenian and georgian": """
        Anahit Ani Araksi Armine Arpi Astghik Gayane Hasmik Hripsime Knarik Lilit
        Lusine Mariam Nairi Nare Nune Satenik Seda Shushan Siranush Sona Takuhi
        Varduhi Zabel Zaruhi
        Dali Eka Ketevan Khatuna Maia Manana Mzia Nana Natela Nato Nestan Nino
        Rusudan Salome Shorena Sopho Tamta Teona Tinatin Tsiala
    """,
    "the old river kingdoms": """
        Ahassunu Aya Beltani Enheduanna Ereshkigal Geshtinanna Gula Iltani Inanna
        Ishara Ishtar Kubaba Lamassi Nanshe Nidaba Nikkal Ningal Ninkasi Ninlil
        Ninsun Puabi Sabitum Shala Shibtu Taram Tashmetum
        Ahhotep Baketaten Hatshepsut Henutsen Henuttawy Hetepheres Iset Isetnofret
        Khentkawes Kiya Meresankh Merit Meritamun Mutemwia Mutnofret Nebet
        Nefertari Nefertiti Neferu Neith Nitocris Nodjmet Nubkhas Satamun Seshat
        Sitre Sobekneferu Takhat Tawosret Tey Tiye Tuya
    """,
    "african": """
        Abena Abiola Achieng Adaeze Adanna Adenike Adunni Adwoa Afia Akinyi Akosua
        Akua Ama Amani Amara Aminata Aster Atieno Awa Ayana Ayo Ayodele Binta Bisi
        Chiamaka Chidinma Chinwe Chioma Desta Dumebi Ebere Efua Ese Eshe Etenesh
        Fatou Fola Folami Funmilayo Hiwot Ifeoma Ijeoma Imani Kadiatou Kamaria
        Kemi Kesi Lerato Lindiwe Liya Lulu Mahlet Makeda Makena Malaika Mariama
        Meskerem Mpho Nafula Naledi Nandi Ngozi Njeri Nkechi Nneka Nobuhle
        Nokuthula Nomsa Nomvula Nyambura Nyokabi Oluchi Oumou Palesa Rahel
        Refilwe Rokia Saba Sade Salimata Selam Temitope Thandeka Thandi Thembi
        Tigist Titilayo Tsehay Wambui Wanjiru Wubet Yaa Yeshi Yetunde Zanele
        Zawadi Zodwa Zola Zuri
    """,
    "indian": """
        Aditi Ahalya Ambika Amrita Anila Anjali Aparna Asha Bhavani Chandra Charu
        Damayanti Deepa Devika Divya Draupadi Gauri Gita Hema Indu Ishani Jaya
        Jyoti Kalpana Kamala Kaveri Kavya Kunti Lalita Lata Leela Leena Madhavi
        Mala Malati Maya Meena Mohini Nalini Nandini Neela Nirmala Padma Pallavi
        Priya Rekha Rohini Roopa Rukmini Sandhya Sarita Savitri Shakuntala Shanta
        Shobha Sita Sudha Sunita Sushila Swati Tara Uma Usha Vasanti Vidya Vimala
        Yamini
    """,
    "east asian": """
        Ai Aiko Akane Asami Ayame Chie Chiyo Emi Fumiko Haruka Haruko Hotaru
        Kaede Kaori Kazuko Keiko Kiku Kimiko Mai Mariko Megumi Michiko Midori
        Misaki Miyu Nanami Naoko Natsu Noriko Rin Sachiko Sakura Sayuri Setsuko
        Shizuka Tamaki Tomoe Yoko Yoshiko Yuki Yumi
        Fang Hua Jia Jing Lan Lian Ling Mei Ning Qing Rong Shu Ting Xia Xiu Yan
        Yun Eun Hayun Hye Jiyoung Minji Seoyeon Sora Yuna
    """,
    "of the old lists": """
        Dara Kira Yara
    """,
}

MALE = {
    "english": """
        Abel Absalom Adam Ailwin Alan Alard Alban Aldous Aldred Alfred Algar Alwin
        Ambrose Amis Anketil Anselm Arnold Arthur Aubrey Auberon Baldwin Barnaby
        Bardolph Bartholomew Bede Benedict Bennet Bertram Botolph Brice Cedric
        Christopher Clement Colin Crispin Cuthbert Cyprian Denis Dickon Drogo
        Dunstan Edgar Edmund Edric Edward Edwin Egbert Elias Ellis Emery Ernald
        Ethelbert Eustace Everard Francis Fulk Gawain Gerald Gervase Gilbert Giles
        Godard Godfrey Godric Godwin Guy Hal Hamo Hamond Harold Herbert Hereward
        Hob Hobb Hodge Hubert Hugh Humphrey Ingram Ivo Jack Jasper Jem Jenkin
        Jocelyn Josce Kenelm Kit Lambert Lancelot Lawrence Leofric Leofwine
        Leonard Lionel Lovel Martin Matthias Maurice Merrick Miles Ned Nicol Nigel
        Noll Norman Odo Oliver Orderic Osbert Osmund Oswald Oswin Percival
        Peregrine Perkin Piers Quentin Rafe Ralph Randolf Ranulf Raymond Reginald
        Reynold Richard Robert Robin Roger Rowland Sampson Sewell Silas Sim Simkin
        Simon Stephen Swithin Tam Tancred Theobald Thomas Thurstan Tibbot Tobias
        Tobin Tybalt Walt Walter Warin Wat Wick Wilfrid Wilkin William Wulfric
        Wulfstan Wymond Wystan Yorath
        Ansel Archibald Aylmer Bevis Cerdic Davy Digory Durand Eldred Elric
        Everett Fabian Gamel Gareth Goscelin Grimbald Hamlin Hankin Hardwin Harry
        Harvey Herluin Humbert Jeffery Jeremy Julian Kenrick Lamkin Larkin Lucan
        Luke Mark Marmaduke Matthew Maynard Neil Nicholas Osric Paul Payne Peter
        Philip Randall Ranald Saer Sayer Sebastian Serlo Siward Stigand Thurkill
        Turold Wace Walden Waleran Warner Wymarc
    """,
    "old english": """
        Aelfric Aethelred Athelstan Beorn Brihtric Cenric Ceolwulf Cynric Eadric
        Eadwig Ealdred Offa Oslac Penda Sigebert Sigeric Tostig Uhtred Wiglaf
        Wulfhere
    """,
    "irish and scots": """
        Aedan Ailill Art Bran Brendan Brian Cathal Cian Ciaran Colm Conall Conan
        Conn Conchobar Cormac Cuan Daithi Declan Diarmuid Donal Eamon Enda Eoghan
        Fergal Fergus Fiachra Finn Fionn Lorcan Lugh Niall Oisin Oran Padraig
        Ronan Ruairi Seamus Senan Tadhg Tiernan
        Alasdair Angus Calum Coll Dougal Duncan Ewan Fingal Gillies Hamish Iain
        Lachlan Malcolm Murdo Ruaridh Somerled Struan Torquil
        Ailbe Breasal Cairbre Cearbhall Conaire Domhnall Dubhghall Eochaid Faolan
        Fearchar Feidhlim Flann Garbhan Gillespie Kenneth Kentigern Laoghaire
        Lochlann Mael Muiredach Murchadh Ninian Odhran Rian Ruadhan Scanlan
        Setanta Sorley Torna Uisdean Ultan
    """,
    "welsh breton cornish": """
        Aneirin Arwel Bedwyr Bleddyn Cadfael Cadoc Cai Caradog Cynan Dafydd Dai
        Deiniol Dewi Dylan Emrys Geraint Glyn Gruffudd Gwilym Gwion Huw Hywel
        Idris Iestyn Ifan Iolo Ithel Llew Llywelyn Madoc Meirion Morgan Owain
        Peredur Pryderi Rhodri Rhys Taliesin Trystan Tudur
        Arzhel Brieuc Erwan Gwenael Herve Loic Maelan Riwal Tudual Yann Yannick
        Jago Jory Kitto Pasco Petroc Ruan
        Alun Bryn Cadell Cledwyn Elfed Elis Emlyn Gethin Goronwy Gwynfor Hefin
        Iorwerth Ivor Macsen Maredudd Owen Pedr Rhydian Selwyn Tegid Teilo Tomos
        Wyn Briac Goulven Jakez Konan Malo Morvan Tanguy Yaouen Austol Gerens
        Hedrek Jowan Lowen Mighal Piran Talan
    """,
    "norse": """
        Agnar Alf Alrik Alvar Anders Arnbjorn Arne Asbjorn Asgeir Askel Asmund
        Atli Audun Axel Bard Bergthor Bersi Birger Bjarni Bjorn Bo Bodvar Bolli
        Bragi Brand Dag Egil Einar Eirik Erland Erlend Eskil Eyvind Finnbogi Flosi
        Folke Frodi Geir Gisli Gorm Grim Gudmund Gunnar Gunnbjorn Gustav Guthrum
        Hagen Hakon Halfdan Hallbjorn Hallstein Hallvard Harald Hauk Hedin Helgi
        Herjolf Hjalmar Hogni Holger Hrafn Hroald Hrolf Ingemar Ingolf Ingvar Ivar
        Jens Joakim Jorund Ketil Kjell Knut Kol Kolbein Lars Leif Ljot Magnus Mats
        Nils Njal Odd Olaf Ole Orm Ottar Per Ragnar Rasmus Rolf Runolf Sigmund
        Sigurd Skeggi Snorri Steinar Sten Styr Sune Svein Sverre Thorfinn Thorgeir
        Thorkel Thorolf Thorstein Thorvald Toki Torbjorn Tore Torsten Trygve Ture
        Ulf Ulfar Vagn Valgard Vemund Vidar Viggo Yngvar
        Arnfinn Arngrim Asvald Atle Brodd Eilif Eldgrim Eystein Fridleif Geirmund
        Glum Gunnlaug Hallfred Hallkel Hastein Hemming Hergrim Hrafnkel Ingjald
        Kalf Kodran Kormak Ljotolf Ofeig Ogmund Onund Orlyg Ospak Ozur Sighvat
        Skuli Steinthor Sturla Svan Thjodolf Thorbrand Thord Thorir Thrain Ulfljot
        Valbrand Vestein
    """,
    "german and frankish": """
        Adalbert Adalric Alaric Albrecht Anno Arbogast Aribert Arnulf Baldric
        Benno Bernhard Berthold Bertolf Bruno Burkhard Carloman Childebert
        Childeric Clovis Conrad Dagobert Detlef Dietrich Eberhard Eckbert Egon
        Ekkehard Engelbert Ernst Falko Folkmar Gebhard Gerhard Gerold Godehard
        Gottfried Gottschalk Gundobad Gunther Hartmann Hartwig Heinrich Helmold
        Hermann Hildebrand Hugo Ingo Kaspar Konrad Kuno Lambrecht Leopold Liudolf
        Lothar Ludwig Lutz Manfred Markwart Meinhard Norbert Odoacer Ortwin Otto
        Pippin Poppo Rainald Reinhold Reinmar Rudolf Rupert Rutger Siegfried
        Sigismund Thankmar Theoderic Totila Ulrich Utz Volker Volkmar Waldemar
        Walram Walther Wendelin Wernher Wido Wigand Wigbert Willibald Wolfgang
        Wolfram Wulf
        Adalgar Amalric Ansgar Arminius Berengar Bernward Dankwart Eckhart
        Ehrenfried Erhard Gisbert Gunthar Hadubrand Heribert Konradin Lanzo
        Leuthold Liutprand Meginhard Notker Ortlieb Ratbod Reginhard Ruprecht
        Tassilo Thiemo Udo Volkwin Walbert Widukind Winfried
    """,
    "french": """
        Achille Adhemar Aimeric Alain Amaury Anatole Armand Arnaud Aubin Audric
        Aurele Aymar Baptiste Bastien Benoit Bertrand Blaise Bohemond Cesaire
        Corentin Cyprien Damien Eloi Enguerrand Etienne Fabrice Florent Fulbert
        Gaspard Gaston Gautier Gauthier Geoffroi Gerard Gerbert Gilles Guilhem
        Guillaume Gustave Hardouin Henri Hilaire Hugues Ignace Jacques Jehan
        Josselin Jourdain Lancelin Leandre Lucien Marius Mathurin Maxence Mederic
        Michel Octave Olivier Onfroi Pascal Philibert Raimond Raoul Remi Renaud
        Roland Romain Sebastien Serge Tancrede Thibault Tristan Valentin Victor
        Xavier Yvain Yves Zacharie
        Achard Adelard Alexandre Aristide Augustin Bernard Bertin Charles Firmin
        Florian Gabin Gervais Gregoire Guerin Honore Hyacinthe Jules Lazare Leon
        Lothaire Louis Marcel Marcellin Mathieu Maurin Nicolas Noel Philippe
        Pierre Prosper Regis Rodolphe Sylvain Thierry Timothee Urbain Vivien
    """,
    "roman and italian": """
        Aelius Agrippa Albinus Antonius Appius Aulus Brutus Caius Cassius Cato
        Claudius Cornelius Crispus Decimus Drusus Fabius Faustus Felix Flavius
        Gaius Galba Gnaeus Horatius Julius Junius Lentulus Lucius Marcus Maximus
        Numa Octavius Otho Petronius Quintus Remus Rufus Sabinus Septimus Servius
        Sextus Silvanus Spurius Tacitus Tiberius Titus Tullus Valerius Varro
        Aldo Alessio Ambrogio Amedeo Andrea Angelo Baldassare Bartolo Benvenuto
        Carlo Corrado Cosimo Dante Donato Enzo Ercole Ettore Fabrizio Federico
        Filippo Gherardo Giacomo Giotto Giulio Guido Lapo Leonardo Lodovico
        Lorenzo Luca Matteo Niccolo Orlando Ottavio Piero Pietro Raffaele Renzo
        Rinaldo Salvatore Sandro Taddeo Tommaso Uberto Ugo Valerio Vittorio
        Aemilius Augustus Gallus Laelius Manius Marcellus Scipio Severus Statius
        Vitus Agostino Alberto Alighiero Anselmo Arnaldo Battista Bonifacio Cesare
        Ciro Dario Duccio Emilio Ezio Fausto Fiorenzo Gaetano Gennaro Gino
        Guglielmo Ippolito Jacopo Leone Manlio Marcello Massimo Nello Pasquale
        Primo Rocco Romolo Saverio Silvio Tancredi Tullio Vito
    """,
    "greek": """
        Achilles Aeneas Agathon Ajax Alcaeus Alexios Andreas Andronikos Aristides
        Ariston Basil Bion Castor Chares Cleon Cyril Damon Demetrios Diogenes Dion
        Eudoxus Evander Glaukos Gregor Hector Hesiod Hippias Homer Iason Isidor
        Kallias Konstantin Kosmas Kyros Leandros Leonidas Linus Lykos Lysander
        Menelaos Myron Nestor Nikandros Nikias Nikolaos Orestes Pallas Panos
        Pericles Petros Philon Phokas Photios Plato Pollux Priam Ptolemy Pyrrhus
        Simonides Socrates Solon Spyros Stavros Stelios Teucer Thales Theodoros
        Theon Timon Vasilis Xenon Yannis Zeno
        Alexandros Alkimos Archelaos Chrysanthos Dimitris Dorotheos Euclid
        Eugenios Hilarion Ioannis Kleitos Kostas Lambros Markos Miltiades
        Nikephoros Pantelis Pavlos Philippos Prokopios Sophokles Stephanos
        Theodosios Xenophon Zenon
    """,
    "hebrew": """
        Aaron Abner Amos Amram Ari Asher Avi Barak Benjamin Boaz Caleb Dan Eli
        Eliezer Elkanah Enoch Ephraim Ezekiel Ezra Gad Gershom Gideon Hillel Hosea
        Ira Isaac Ishmael Jacob Japheth Jared Jethro Joab Joel Jonah Jonathan
        Joshua Josiah Judah Laban Levi Malachi Micah Mordecai Moshe Nahum Naphtali
        Nathan Nathaniel Noam Obadiah Obed Reuben Saul Seth Shem Simeon Tobiah
        Uriah Uriel Yitzhak Yonah Yosef Zadok Zebulun Zechariah
        Abiel Adiel Amichai Asaf Azariah Baruch Benaiah Chaim Dov Eitan Elazar
        Elisha Ilan Ittai Mattan Meir Menachem Nadav Omri Oren Shai Shimon Tal
        Yair Yehuda Yoav Zev
    """,
    "slavic": """
        Aleksei Arkady Bartek Bogdan Bogumil Bolek Boleslav Borislav Boris
        Branislav Bronislav Casimir Czeslaw Dalibor Damjan Danil Danilo Dmitri
        Dobromir Dragan Dragomir Dusan Fyodor Gleb Gorazd Gostislav Grigori Igor
        Ilya Jacek Janusz Jarek Jaromir Jaroslav Kazimir Kirill Kostya Kresimir
        Kuba Lech Lev Ljubomir Ludomir Luka Makar Maksim Marek Matej Mieszko
        Mikhail Milan Milos Miroslav Mstislav Nebojsa Nikita Ognjen Oleg Pavel
        Predrag Premysl Pyotr Radek Radomir Radoslav Ratimir Rodion Rostislav
        Ruslan Semyon Slavomir Stanislav Stepan Stojan Svatopluk Svyatoslav
        Tadeusz Tihomir Timofei Tomislav Vaclav Vadim Vasili Velimir Vladimir
        Vladislav Vlastimil Vojtech Vratislav Vsevolod Witold Wojciech Yakov
        Yaropolk Yegor Yuri Zakhar Zbigniew Zdenek Zelimir Ziemowit Zoran
        Zvonimir
        Andrzej Bohdan Bohumil Borivoj Branko Budimir Cedomir Danko Darko Davor
        Dobroslav Goran Grzegorz Hrvoje Ivan Jan Jure Krzysztof Lubomir Mladen
        Mojmir Momcilo Nenad Nikola Ostoja Petar Radovan Rajko Ratko Sava Slobodan
        Srdan Stanko Velko Vuk Zarko Zivko Afanasy Anatoly Andrei Artyom Efim
        Fedot Foma Gennady Kuzma Matvei Nazar Nikolai Ostap Pankrat Platon Prokhor
        Savva Taras Trofim Yaroslav Zinovy
    """,
    "baltic": """
        Algirdas Andris Arunas Arvids Dainis Darius Dovydas Edgars Gatis
        Gediminas Ivars Janis Jonas Juris Kestutis Maris Mindaugas Raimonds Rimas
        Saulius Uldis Valdis Vilius Vytautas
        Aidas Aigars Aivars Ansis Audrius Domas Eimantas Gintaras Ilmars Kaspars
        Kazys Linas Mantas Rokas Tomas Vaidas Viesturs
    """,
    "finnish estonian sami": """
        Aare Aarne Aatos Ahti Ailo Ants Antero Arvo Aslak Eero Eino Endel Heikki
        Heino Ilkka Ilmari Into Jaakko Jaan Jussi Kaapo Kalevi Kalju Kalle Kauko
        Lauri Lembit Martti Matti Meelis Mihkal Mikko Oiva Olli Onni Osmo Paavo
        Peeter Pekka Rein Reino Risto Sakari Sampo Seppo Taisto Tapio Tarmo Timo
        Toivo Toomas Tonu Tuomas Uku Uljas Ukko Unto Urho Urmas Vaino Valto
        Veikko
    """,
    "hungarian": """
        Almos Arpad Attila Bela Bence Botond Bulcsu Csaba Endre Ferenc Gabor Geza
        Gyula Huba Imre Istvan Janos Kalman Kende Koppany Laszlo Lehel Levente
        Lorinc Miklos Szabolcs Tamas Zoltan Zsolt
        Agoston Aladar Ambrus Barnabas Boldizsar Dezso Elek Erno Gergely Gusztav
        Jeno Kristof Lajos Marton Mate Mihaly Nandor Orban Pal Sandor Tibor Vince
    """,
    "basque": """
        Aitor Ander Asier Benat Eneko Gaizka Gorka Iban Ibai Inaki Jon Joseba Kepa
        Koldo Mikel Oier Patxi Txomin Unai Urko Xabier Zigor
        Andoni Ekaitz Endika Haritz Imanol Josu Julen Markel
    """,
    "spanish and portuguese": """
        Afonso Alfonso Alonso Alvaro Bermudo Bernardo Diego Domingo Duarte
        Esteban Fadrique Fernan Fernando Garcia Gaspar Goncalo Gonzalo Gutierre
        Henrique Inigo Jaime Joaquin Leandro Lope Lucio Manrique Mateo Mendo
        Nicanor Nuno Ordono Pelayo Rafael Ramiro Rodrigo Rui Ruy Sancho Santiago
        Tello Teodoro Tiago Vasco Velasco Ximeno
        Abelardo Agustin Alejandro Amador Arturo Benigno Celestino Cristobal
        Damian Eduardo Enrique Ernesto Eugenio Felipe Fermin Florencio Gabriel
        Gerardo Guillermo Hernan Hernando Ignacio Isidro Javier Jeronimo Jorge
        Luis Manuel Marcos Mariano Pablo Pascual Pedro Ramon Raul Salvador Vicente
        Bento Fernao Gil Lourenco Martim Paio
    """,
    "persian": """
        Afshin Arash Ardashir Babak Bahram Bardiya Behnam Bijan Darab Dariush
        Esfandiar Farhad Fariborz Fereydun Hormoz Hushang Iraj Jamshid Kambiz
        Kamran Kaveh Khosrow Kourosh Mani Manuchehr Mazdak Mehrdad Nader Parviz
        Payam Peyman Ramin Rostam Sam Shahin Shapur Siavash Sohrab Vahid Zal
        Ashkan Bahman Ehsan Firouz Goudarz Hesam Kasra Keyvan Khashayar Mahyar
        Mehran Milad Navid Omid Pouya Saman Shahrokh Shervin Sina Soroush Teymour
    """,
    "arabic": """
        Abbas Adel Adnan Ahmad Ali Amir Anwar Ayman Bashir Bilal Fadi Faisal Farid
        Fuad Ghassan Habib Hadi Hamza Harun Hashim Hassan Hisham Husam Ibrahim
        Imad Isa Jabir Jalal Jamal Jawad Kamal Karim Khalid Luay Mahmud Malik
        Mansur Marwan Mazin Munir Musa Nabil Nadir Nasir Nizar Omar Qasim Raed
        Rafiq Rashid Rida Saad Said Salah Salim Sami Shadi Talal Tariq Wael Walid
        Yahya Yasin Yusuf Zaid Zakariya Ziyad
        Ammar Asim Ayyub Badr Basim Dawud Fahd Fawzi Hakim Hamid Haytham Ilyas
        Ismail Jafar Kadir Khalil Laith Mahir Mamun Murad Mustafa Nadim Naeem Nuri
        Rami Riyad Sabir Sadiq Shakir Suhail Tahir Tamim Wasim Yazid Zahir Zuhair
    """,
    "turkish and steppe": """
        Aibek Almaz Alp Altan Arman Arslan Askar Azamat Aydin Bakyt Baris Batu
        Bora Bulut Burak Cem Cengiz Daulet Deniz Emre Erlan Ertugrul Galip Gokhan
        Kaan Kanat Kemal Kerem Kutlu Mete Murat Nurlan Orhan Osman Ozan Selim
        Serik Serkan Tarkan Temir Timur Tolga Tugrul Umut Volkan Yavuz Yerlan
        Yigit
        Bahadir Berk Bilge Caner Cihan Dogan Erdem Eren Erkan Ferit Hakan Ilhan
        Kagan Korkut Mert Oguz Onur Ozgur Sinan Tamer Toprak Ugur Yunus Abai
        Baurzhan Dauren Ermek Kairat Marat Talgat Zhandos
    """,
    "armenian and georgian": """
        Aram Arshak Artashes Ashot Davit Gagik Garegin Gevorg Grigor Hayk
        Hovhannes Levon Mesrop Mher Narek Samvel Sargis Smbat Tigran Vahagn
        Vardan Zaven
        Amiran Bagrat Gela Giorgi Guram Ioane Irakli Lasha Levan Merab Nodar Otar
        Revaz Shota Tamaz Vakhtang Zurab
        Ara Armen Arsen Avetis Gurgen Hrant Karapet Nerses Ruben Sevak Suren
        Varazdat Vazgen Archil Avtandil Beka Dachi Erekle Ilia Kakha Mamuka
        Nikoloz Paata Rati Tariel Teimuraz Vazha Zviad
    """,
    "the old river kingdoms": """
        Adapa Akurgal Ashur Atrahasis Dumuzi Enkidu Enmerkar Etana Gilgamesh Gudea
        Hammurabi Iddin Lugalbanda Marduk Nabu Nergal Ninurta Puzur Rimush Sargon
        Shamash Shulgi Utu Zimri Ziusudra
        Ahmose Akhenaten Amenemhat Amenhotep Anhur Ankhu Djedi Djoser Hapu
        Harkhuf Horemheb Imhotep Ineni Ipuwer Kagemni Kamose Kha Khafre Khufu
        Menes Menna Merenre Nakht Narmer Nebamun Paser Pepi Ptahhotep Ramose
        Rekhmire Sahure Senenmut Sennedjem Seti Sneferu Sobekhotep Thutmose Unas
        Userkaf Weni Yuya
        Ilushuma Ishme Ninazu Tudiya Ubartutu Zabaia Hori Huy Intef Kheti
        Merneptah Neferhotep Psamtek Seqenenre Taharqa Tutankhamun Wenamun
    """,
    "african": """
        Abebe Adebayo Adisa Amare Babajide Bekele Bongani Chidi Chike Chinedu
        Dawit Dumisani Ekene Emeka Femi Gyasi Haile Jabari Jelani Juma Kagiso
        Kamau Kato Kayode Kimani Kiprono Kipchoge Kofi Kwabena Kwaku Kwame Kwasi
        Lwazi Mandla Mensah Mosi Mwangi Njoroge Nnamdi Obi Obinna Ochieng
        Odhiambo Olu Oluwaseun Otieno Sefu Sipho Sizwe Tau Tesfaye Tewodros Thabo
        Themba Tunde Uzoma Wekesa Yared Yaw Yohannes Zuberi
        Adama Akin Amadou Ayodeji Babatunde Bheki Chukwuma Daudi Ebo Ekow Fiifi
        Ifeanyi Ikenna Jomo Kelechi Kobina Kojo Kwesi Lamine Mamadou Moussa
        Mthunzi Nathi Ngugi Nkosana Olumide Oumar Sekou Seydou Sibusiso Siyabonga
        Tafari Tendai
    """,
    "indian": """
        Aditya Ajay Ananda Arjuna Arun Ashok Bharat Bhima Chandan Dev Dhruva
        Gautam Govind Hari Jai Kabir Karna Kiran Lakshman Madhav Mahesh Mohan
        Nakul Nanda Narayan Nikhil Pranav Raghu Rahul Raj Ravi Rohan Sahadev
        Sanjay Shankar Siddharth Suresh Tarun Uday Vasu Vikram Vinod Yash
        Abhay Akash Amar Anil Arvind Balram Chetan Deepak Dinesh Hemant Ishaan
        Jatin Kailash Kartik Keshav Lalit Manish Mukesh Naveen Nitin Pavan Pradeep
        Prakash Rajendra Rakesh Sameer Satish Shyam Sunil Tushar Varun Vijay Vivek
        Yogesh
    """,
    "east asian": """
        Akio Daichi Haruto Hideo Hiro Isamu Jiro Kaito Kenji Kenta Masaru Minoru
        Noboru Ren Ryo Saburo Shiro Takeshi Taro
        Bao Chen Hao Jun Kang Lei Ming Wei Yong Zhen
        Cheol Hyun Jae Joon Seok Sung Tae Woo
        Haruki Hayato Ichiro Katsu Kazuo Kenshin Kiyoshi Makoto Michio Naoki Osamu
        Ryota Satoru Shin Sho Sota Susumu Tadashi Takumi Tetsuo Yoshiro Yuto Feng
        Gang Guang Jian Liang Qiang Shan Tao Xin Yu Zhi Dae Ho Hoon Jin Sang Soo
    """,
    "of the old lists": """
        Fen Lomax Nol Pip
    """,
}


def build(groups):
    seen = []
    have = set()
    for words in groups.values():
        for name in words.split():
            if name not in have:
                have.add(name)
                seen.append(name)
    return sorted(seen)


def shipped_text():
    data = {"female": build(FEMALE), "male": build(MALE)}
    return json.dumps(data, indent=1) + "\n"


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def check(fail):
    for sex, groups in (("female", FEMALE), ("male", MALE)):
        every = [n for words in groups.values() for n in words.split()]
        names = build(groups)
        twice = sorted({n for n in every if every.count(n) > 1})
        if twice:
            fail.append("%s names listed twice (keep one): %s" % (sex, ", ".join(twice[:20])))
        if len(names) < MIN_EACH:
            fail.append("only %d %s names; at least %d" % (len(names), sex, MIN_EACH))
        bad = [n for n in names if not SHAPE.match(n) or len(n) > LONGEST]
        if bad:
            fail.append("%s names that are not one plain capitalised word of at most %d letters: %s"
                        % (sex, LONGEST, ", ".join(bad[:20])))
        banned = sorted(set(names) & NEVER)
        if banned:
            fail.append("%s names this game will not use: %s" % (sex, ", ".join(banned)))
        print("  %-6s %4d names from %d traditions" % (sex, len(names), len(groups)))
    if not OUT.exists() or OUT.read_text() != shipped_text():
        fail.append("data/villager_names.json is not what these lists make: "
                    "run python3 tools/villager_names.py --write")
    script = (ROOT / "scripts/villager/villager_names.gd").read_text()
    villager = (ROOT / "scripts/villager/villager.gd").read_text()
    if 'const FILE := "res://data/villager_names.json"' not in script \
            or "JSON.parse_string(" not in body(script, "_read_file") \
            or "FALLBACK_FEMALE" not in body(script, "_read_file"):
        fail.append("VillagerNames does not read the names file, "
                    "or has no names for the day it is missing")
    if "VillagerNames.pick(" not in body(villager, "_random_name") or "FEMALE_NAMES" in villager:
        fail.append("a villager is named from a list of its own again, not from VillagerNames")
    pick = body(script, "pick")
    if "given.has(" not in pick or "given[chosen] = true" not in pick:
        fail.append("a town hands out names it has already given")
    village = (ROOT / "scripts/world/village.gd").read_text()
    migrant = (ROOT / "scripts/villager/migrant.gd").read_text()
    if "VillagerNames.bring_back(" not in body(village, "_restore_villager") \
            or "VillagerNames.forget(self)" not in body(village, "from_dict") \
            or "VillagerNames.claim(" not in body(migrant, "raise"):
        fail.append("somebody brought back under their own name "
                    "is not counted as named in their town")
    presets = (ROOT / "export_presets.cfg").read_text()
    filters = re.findall(r'^include_filter="(.*)"$', presets, re.M)
    if not filters or any("*.json" not in f for f in filters):
        fail.append("an export does not ship *.json, "
                    "so it goes out with no names (and no charters)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true", help="regenerate data/villager_names.json")
    args = ap.parse_args()
    if args.write:
        OUT.write_text(shipped_text())
        print("wrote %s" % OUT.relative_to(ROOT))
    fail = []
    print("VILLAGER NAMES")
    check(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
