require "spec"
require "random/pcg32"

describe("Random::PCG32") do
  it("generates random numbers as generated official implementation") do
    numbers = [
      3152259133, 2489095755, 485973489, 739446704, 3084920751,
      2161564962, 2655557215, 4238523805, 4127884210, 1729992006,
      1964292282, 3213125726, 1096479421, 1281102065, 2428306580,
      714078320, 2392099709, 1526439585, 402063061, 987620545,
      3290157899, 3849428442, 3440034864, 979768042, 2581261330,
      697552453, 2701760878, 1629908786, 2263909770, 2396572129,
      2915312060, 1163641977, 3915471724, 2608873459, 926223418,
      3195912237, 4227696621, 3135858064, 4281979580, 3933514590,
      2043026875, 2382205407, 1676050888, 3865582612, 2156465812,
      475741448, 1441007193, 1068412521, 3443013050, 2606006740,
      3917347556, 3545411947, 1285806801, 3233203743, 83808518,
      2316494619, 3094051679, 4232904961, 556837719, 2364763832,
      2985639445, 2764876339, 3794480974, 3218650203, 394445985,
      3653052187, 3871764828, 3652452072, 3211653627, 3072401364,
      3312575786, 1434335361, 3589384991, 1880518631, 4154909753,
      781856932, 2958234005, 2215042200, 3989578033, 2724202193,
      3276287024, 3857960173, 3261972894, 1278127551, 2910186591,
      1318442819, 1732089978, 1226233120, 1610882785, 2555776835,
      2827209191, 2550397788, 879181699, 4111486503, 1424052202,
      592749904, 181272803, 2052719404, 1464274999, 3191236557,
      4035072851, 2447786701, 1508789148, 2949852022, 1596672675,
      874908458, 1083828097, 4128737369, 2892752832, 4161975140,
      4063766939, 116721858, 3549607777, 2875310346, 2521462935,
      2611783422, 289182647, 3434103775, 3694998243, 1756960730,
      424818697, 2125655315, 137915754, 308167565, 500350518,
      4225198488, 3208597443, 4120593227, 886307125, 2810197833,
      1046810634, 2248715633, 1732273418, 3297629623, 3909267631,
      2814215577, 542536551, 3821842943, 2706123873, 4023610128,
      3718248286, 2681796329, 552208177, 543429826, 1023723652,
      926924173, 3304944984, 3498001447, 3910350161, 2173595067,
      1572275538, 3746362970, 3921531055, 4275984385, 1107615065,
      798885450, 593701507, 746831642, 2380742034, 2662553742,
      784679570, 2898603226, 2654863246, 4188102213, 3404287149,
      2457824074, 1611786778, 2774875692, 3214028852, 3474269753,
      638991533, 2876947025, 224837420, 3427610759, 637796298,
      872913304, 230900522, 2497845134, 1231922500, 3186038255,
      2231895999, 4145622422, 4127438182, 123440798, 2445812013,
      742589188, 1597895892, 136729449, 2068901076, 3483340503,
      2142045847, 3370920004, 4110699246, 896685970, 2705758845,
      2429759267, 2634038519, 3803282661, 102147536, 2662802352,
      2928194559, 1789601722, 3273475405, 595247591, 1920554561,
      1357591722, 1148716171, 2883327948, 3559357577, 2590089812,
      3793391831, 4294783876, 2576298305, 1346833391, 616223245,
      358458145, 2954013630, 2458708274, 3488150452, 2978472547,
      3730992200, 1800033499, 1021364745, 3209833714, 532534773,
      1759755310, 3848259511, 228695388, 1511557673, 1375696353,
      4070021632, 853659457, 902039725, 3752410041, 663810756,
      3640029827, 408533623, 979227213, 2241726534, 2011792749,
      1554143644, 1777460466, 3941988208, 680305025, 2527117533,
      2900559404, 149303676, 1469465181, 427361544, 3025171681,
      1467079836, 4047295972, 1260499396, 923706251, 1622637410,
      3088110035, 3598131931, 3212854712, 70471773, 2957552528,
      3151895712, 1633306458, 2394973777, 3119598452, 3022402606,
      255688883, 1168220288, 1460799618, 3267323738, 220323701,
      1578402126, 4250490965, 3077459240, 1160973232, 351701933,
      2784720542, 1394167841, 4051721212, 371952896, 1973783929,
      3648107670, 1530583910, 1832329814, 4086713855, 3803165377,
      2199487219, 198963646, 2272747406, 1279141576, 3437303601,
      2092147571, 1420523853, 4008430746, 2521394822, 750977764,
      4014788147, 885313409, 2183347471, 3910873069, 3206967476,
      1343983830, 4090065941, 1080284715, 2544279422, 2536660066,
      83397412, 376958746, 3342775199, 198656073, 3396903609,
      3690557488, 935801910, 2874380889, 710255514, 1143584976,
      1659398432, 1995953899, 3787661179, 279487606, 1884931545,
      3722215215, 2804487811, 949797573, 270526480, 1999556782,
      1705597493, 4194847978, 2994245091, 2200536670, 4043146221,
      2300185633, 3315527543, 1806052579, 2147999232, 4283687644,
      3966597571, 3030769992, 2829105814, 1990560906, 3809025954,
      304899011, 1308237895, 918475845, 2863237781, 2950130665,
      187348261, 44475868, 3752100000, 1438913640, 3698251096,
      3058136087, 3870845878, 734965319, 3932015010, 2228969989,
      1438075944, 4145352926, 1447116330, 987733624, 740850530,
      545170763, 3490076022, 1824981371, 2897520939, 680528095,
      1043360829, 2471400869, 2531242384, 1391866181, 3919001970,
      2669153449, 2349636350, 1610505852, 2040603403, 1066161728,
      1816628151, 891920597, 1618871135, 3722751414, 2572659388,
      149615482, 422329046, 1346243966, 152859188, 3912095940,
      474646586, 3355907871, 3507474089, 915715720, 89939149,
      2088699533, 92635730, 3617261580, 671224575, 387783436,
      1720494999, 865234509, 1391451431, 231801218, 3216862605,
      3059903310, 191182363, 2064527674, 3976550135, 2775767657,
      846710684, 3649614275, 459607853, 4042595156, 1746468842,
      2169842137, 1133125375, 43074024, 557721941, 2327490727,
      4291814753, 526549723, 3772505931, 2304757232, 3687648692,
      3205823216, 4005885424, 1464992250, 677775161, 3713603155,
      225238780, 3195539494, 2659534492, 4240749843, 4230190397,
      2977774409, 1116631315, 2736451989, 2648644420, 4043663805,
      3438094951, 2175224133, 1963295755, 1903595797, 1307902629,
      1660488095, 3387264330, 373454731, 2028059229, 2054707911,
      3718875197, 584167931, 1731683340, 3814377540, 4078714056,
      2801037738, 623721081, 1009162266, 416339462, 1816872628,
      4097234983, 3658943599, 3231023243, 2503322097, 779699657,
      3466123881, 845081479, 3901529354, 1204428463, 4138880724,
      4229825258, 421584796, 773918038, 1437363947, 2537882002,
      3639042184, 1397752119, 1514231515, 3879786050, 468999209,
      3501333333, 2147871873, 3691114017, 2106546687, 1098889611,
      2605749152, 1535872144, 4051831975, 534053246, 2110496658,
      2689253576, 21091593, 2537864165, 682029957, 3857012329,
      3489705216, 3683450242, 2062023254, 526748247, 1651517044,
      3483810301, 1731825610, 511563672, 683235416, 860886303,
      1543813269, 3547121640, 19298476, 1162462965, 603414277,
      1151994135, 767686929, 157925985, 1688172158, 244945727,
      2140029812, 4239900639, 2476037922, 2487753835, 356695600,
      1890908737, 2158904600, 582254963, 625209263, 2056668440,
      2459210833, 3923461372, 1202261374, 1738126538, 658156162,
      858757606, 2277093406, 3331417943, 2712495625, 308115472,
      570054023, 3875689146, 616905744, 3023726697, 1221472646,
      2014618057, 3501313970, 851294431, 552785953, 335861796,
      2817015949, 872689902, 1290307640, 2875122071, 3685219344,
      1621868258, 3956292840, 2687995934, 1453126073, 4264135243,
      610747898, 2683682733, 3011149255, 903812326, 2893971745,
      2125628997, 2928337946, 1366876677, 569570263, 3151177377,
      4293600395, 3668009845, 1746584807, 1560785237, 3128259540,
      2251458057, 980485191, 2801973792, 1838969331, 2378780894,
      2946620064, 1387911045, 3020634335, 3570592525, 1395942741,
      1049354413, 2264450723, 1224667241, 2172202524, 2112895235,
      4165144955, 4287652636, 3450325967, 4195851782, 3548006139,
      2711137513, 587010713, 215680752, 3843539991, 3224825991,
      317923666, 3456980036, 3823856843, 2811490222, 3902228860,
      1468943371, 2447539668, 390310094, 4118745819, 4283390143,
      1491924070, 2524640914, 520462143, 340307971, 1085902276,
      2183059148, 1441406677, 4156585458, 2883152945, 2219938415,
      3949555055, 4066516196, 3870270320, 2162405907, 2122743940,
      4181116623, 2788459158, 2282415566, 33547338, 1456478686,
      2279378290, 1480109803, 2903111377, 3945426414, 2121062997,
      113658340, 3952206955, 3771713683, 1980080742, 1320066490,
      2189636694, 1540806808, 2626922735, 3101538891, 4204072960,
      2394823297, 4260801048, 178857193, 233797511, 475398705,
      2717487817, 2619203653, 3067296452, 975269041, 711727163,
      1806019313, 972009279, 752642597, 2253913949, 378018363,
      3692822806, 2291715909, 3797076961, 1720600028, 1090788534,
      1902148720, 639105200, 451355803, 2514917140, 1623831419,
      1960739521, 1603113582, 669561148, 495359823, 2575690747,
      645045676, 3107783451, 2074524703, 5717861, 3494250223,
      154312986, 1490018548, 3101998594, 923805398, 4084912428,
      752872063, 4055978887, 1553913942, 3395247744, 271319475,
      3230109488, 196118094, 3493398046, 3929019851, 1329081029,
      1975590465, 4114658171, 3256365491, 4255284016, 2330054640,
      1851548018, 2652996931, 3206244712, 2732300088, 3353208910,
      2809477721, 1928547302, 830668350, 1824769219, 679926763,
      3000806510, 2835860144, 773062291, 2592370757, 1624681417,
      1621785075, 13878616, 3564256604, 2214646575, 1998415234,
      1741843641, 106120338, 1149769343, 1985608948, 1758241877,
      675727517, 1345269025, 2036015953, 4124573105, 50515534,
      2824684386, 2257877229, 3401700697, 871828611, 1774662235,
      459169519, 1950903537, 245645886, 2267227716, 3595508053,
      2968185818, 974656384, 4120436926, 1255271843, 2111922304,
      2590233652, 2271784423, 2611180179, 287613450, 984974680,
      2034441466, 2950062628, 1315816115, 1455483087, 4102478979,
      3536667676, 3938550701, 80175511, 3062472660, 4178983616,
      2538339777, 2818121756, 1901212384, 1152628993, 2195262219,
      3379127407, 3518457276, 3384024534, 3547607989, 1641066462,
      2940569625, 352680641, 1816983234, 1278220099, 3565098247,
      398748542, 1557771113, 1173437839, 679670453, 545521558,
      3634129455, 2794896613, 2632809002, 4143379313, 3127719435,
      2991220134, 1191706879, 922765839, 2935804138, 1459299172,
      2913423027, 3519317577, 3051632296, 3515024263, 1205545960,
      214870549, 714375770, 3731434477, 54164339, 1409785122,
      2095886986, 2984072989, 2023326206, 182256043, 2369690875,
      1417209127, 4287385144, 2928838638, 2290207244, 1758239167,
      4265832369, 1039980687, 2055041523, 1686913680, 2572919193,
      2898133024, 3315580132, 3631605988, 3335315781, 3651251993,
      227705262, 2490767375, 4225816603, 2368328128, 1646548309,
      3380964902, 1085548774, 3389065723, 4143107792, 2162197026,
      428406666, 3970339861, 937788473, 25855215, 1768558175,
      277451823, 3827742831, 1927491367, 2411140319, 3143966439,
      3324023500, 472300900, 1766495680, 3732764466, 1142736941,
      2264858589, 3566987973, 2584932467, 1718932167, 1324050561,
      2149264288, 3352290801, 1681118604, 150507558, 884863601,
      3603751545, 3176229599, 1721730780, 944156250, 3674847539,
      2190475248, 1026568815, 2358223767, 1677593454, 3598600855,
      2161822129, 1836298828, 2174358983, 2756163252, 11262953,
      443286989, 195186846, 2259448910, 2925846765, 2317618658,
      537955797, 1692642836, 1493395222, 1166712581, 2162822772,
      2624157077, 261913075, 2517387571, 1959309016, 1919163400,
      2838485297, 3063156449, 3806786018, 4156769566, 3949232856,
      654739052, 3371283799, 2732421937, 669994169, 1791086420,
      3338996392, 2288669419, 307009501, 1782206558, 3584439117,
      1034505656, 4185306586, 2573525195, 1387536053, 2519189134,
      1780764686, 827972414, 1357707228, 4125644428, 351534027,
      1942211948, 1774218210, 1427464762, 558923619, 1691636337,
      3969245170, 1120085618, 3619440303, 2298981826, 3298710585,
      811275286, 1512365269, 570153323, 1259558917, 3970256463,
      557482421, 1119928138, 3377181702, 2865140105, 1695073349,
      1616464886, 3327154569, 1447770430, 3492782369, 105460008,
      2218941048, 2932446555, 42703369, 2176925470, 3827613738,
      3155341484, 3510028168, 2824636097, 889570783, 82606235,
      1679203450, 1442980090, 1257995638, 3964360852, 306536899,
      4265338980, 3087927660, 2400741951, 2530954085, 142645944,
      2800445979, 1715385912, 2269077321, 674552406, 4170469914,
      3626918117, 4069600062, 1412694875, 458758489, 4150188116,
      1263319500, 1904437305, 3988056128, 3983207806, 3788270062,
      3126263147, 752216999, 130388335, 1249773541, 2546985244,
      3895008020, 3269892779, 3586920839, 1707477586, 1529026373,
      907423954, 1466533845, 3979231884, 3830238796, 882835283,
      305587680, 3809630881, 4272299545, 586326910, 2393718249,
      1400136727, 4006138046, 2671692572, 306965616, 2706776810,
      1931034729, 3437103677, 3885893079, 1451834709, 834357077,
      1734264296, 1789084544, 2581055613, 2664601835, 423470342,
      1806201888, 2950983606, 1725641904, 3802798623, 3660813410,
    ]
    seed = {123_u64, 456_u64}

    m = Random::PCG32.new(*seed)
    numbers.each do |n|
      m.next_u.should eq(n)
    end
  end

  it("can jump ahead") do
    seed = {123_u64, 456_u64}

    m1 = Random::PCG32.new(*seed)
    m2 = Random::PCG32.new(*seed)
    10.times { m1.next_u }
    m2.jump(10)
    m1.next_u.should eq m2.next_u
  end
  it("can jump back") do
    seed = {123_u64, 456_u64}

    m1 = Random::PCG32.new(*seed)
    m2 = Random::PCG32.new(*seed)
    10.times { m1.next_u }
    m1.jump(-10)
    m1.next_u.should eq m2.next_u
  end

  it("can be initialized without explicit seed") do
    Random::PCG32.new.should be_a Random::PCG32
  end
end
