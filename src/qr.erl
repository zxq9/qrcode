%% Copyright 2011 Steve Davis <steve@simulacity.com>
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.

-module(qr).

-export([decode/1,
         encode/1, encode/2, encode_png/1, encode_png/2]).

-record(qrcode, {version, ecc, dimension, data}).

-record(qr_params, {mode, version, dimension, ec_level, block_defs, align_coords, remainder, mask, data}).

-define(QR_GF256_PRIME_MODULUS, 285). % 16#011D -> 2^8 + 2^4 + 2^3 + 2^2 + 1

-define(VERSION_INFO_POLY, 7973). % 16#1f25 -> 0001 1111 0010 0101
-define(FORMAT_INFO_POLY, 1335).  % 16#0537 -> 0000 0101 0011 1110
-define(FORMAT_INFO_MASK, 21522). % 16#5412 -> 0101 0100 0001 0010

-define(QUIET_ZONE, 4). % recommended value

%% Table 2. Mode Indicator
-define(TERMINATOR, 0).
-define(NUMERIC_MODE, 1).
-define(ALPHANUMERIC_MODE, 2).
-define(STRUCTURED_APPEND_MODE, 3).
-define(FNC1_FIRST_POSITION_MODE, 5).
-define(BYTE_MODE, 4).
-define(ECI_MODE, 7).
-define(KANJI_MODE, 8).
-define(FNC1_SECOND_POSITION_MODE, 9).

%% Table 3. Number of bits in Character Count Indicator
%% {Mode, [v0-v9, v10-v26, v27-v40]}
-define(CCI_BITSIZE, [
	{?NUMERIC_MODE, [10, 12, 14]},
	{?ALPHANUMERIC_MODE, [9, 11, 13]},
	{?BYTE_MODE, [8, 16, 16]},
	{?KANJI_MODE, [8, 16, 16]}
]).

% Table 5. Alphanumeric charset - see also char/1 
-define(CHARSET, <<"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:">>).
-define(ALPHANUMERIC_REGEX, <<"[", ?CHARSET/binary, "]+">>).
-define(NUMERIC_REGEX, <<"[0123456789]+">>).

% Section 8.4.9
-define(DATA_PAD_0, 236). % 11101100
-define(DATA_PAD_1, 17).  % 00010001

%% Annex E. Table E.1 - Origin at 1, 1 rather than 0, 0
-define(ALIGNMENT_COORDINATES, {
	[],
	[7, 19],
	[7, 23],
	[7, 27],
	[7, 31],
	[7, 35], 
	[7, 23, 39], % Version 7
	[7, 25, 43], 
	[7, 27, 47], 
	[7, 29, 51],
	[7, 31, 55], 
	[7, 33, 59], 
	[7, 35, 63], 
	[7, 27, 47, 67], % Version 14 
	[7, 27, 49, 71],
	[7, 27, 51, 75], 
	[7, 31, 55, 79], 
	[7, 31, 57, 83], 
	[7, 31, 59, 87], 
	[7, 35, 63, 91],
	[7, 29, 51, 73, 95], % Version 21
	[7, 27, 51, 75, 99], 
	[7, 31, 55, 79, 103], 
	[7, 29, 55, 81, 107], 
	[7, 33, 59, 85, 111],
	[7, 31, 59, 87, 115], 
	[7, 35, 63, 91, 119], 
	[7, 27, 51, 75, 99, 123], % Version 28
	[7, 31, 55, 79, 103, 127],
	[7, 27, 53, 79, 105, 131],
	[7, 31, 57, 83, 109, 135],
	[7, 35, 61, 87, 113, 139],
	[7, 31, 59, 87, 115, 143],
	[7, 35, 63, 91, 119, 147],
	[7, 31, 55, 79, 103, 127, 151], % Version 35
	[7, 25, 51, 77, 103, 129, 155],
	[7, 29, 55, 81, 107, 133, 159],
	[7, 33, 59, 85, 111, 137, 163],
	[7, 27, 55, 83, 111, 139, 167],
	[7, 31, 59, 87, 115, 143, 171] % Version 40
}).

% Composite of Tables 1, 7-11, 13-22
% {{level, version},
%  {numeric_capacity, alpha_capacity, byte_capacity, kanji_capacity},
%  ecc_blocks[{number_of_blocks, total_bytes, data_bytes], remainder_bits}
-define(TABLES, [
	{{'L',1},{41,25,17,10},[{1,26,19}],0},
	{{'L',2},{77,47,32,20},[{1,44,34}],7},
	{{'L',3},{127,77,53,32},[{1,70,55}],7},
	{{'L',4},{187,114,78,48},[{1,100,80}],7},
	{{'L',5},{255,154,106,65},[{1,134,108}],7},
	{{'L',6},{322,195,134,82},[{2,86,68}],7},
	{{'L',7},{370,224,154,95},[{2,98,78}],0},
	{{'L',8},{461,279,192,118},[{2,121,97}],0},
	{{'L',9},{552,335,230,141},[{2,146,116}],0},
	{{'L',10},{652,395,271,167},[{2,86,68},{2,87,69}],0},
	{{'L',11},{772,468,321,198},[{4,101,81}],0},
	{{'L',12},{883,535,367,226},[{2,116,92},{2,117,93}],0},
	{{'L',13},{1022,619,425,262},[{4,133,107}],0},
	{{'L',14},{1101,667,458,282},[{3,145,115},{1,146,116}],3},
	{{'L',15},{1250,758,520,320},[{5,109,87},{1,110,88}],3},
	{{'L',16},{1408,854,586,361},[{5,122,98},{1,123,99}],3},
	{{'L',17},{1548,938,644,397},[{1,135,107},{5,136,108}],3},
	{{'L',18},{1725,1046,718,442},[{5,150,120},{1,151,121}],3},
	{{'L',19},{1903,1153,792,488},[{3,141,113},{4,142,114}],3},
	{{'L',20},{2061,1249,858,528},[{3,135,107},{5,136,108}],3},
	{{'L',21},{2232,1352,929,572},[{4,144,116},{4,145,117}],4},
	{{'L',22},{2409,1460,1003,618},[{2,139,111},{7,140,112}],4},
	{{'L',23},{2620,1588,1091,672},[{4,151,121},{5,152,122}],4},
	{{'L',24},{2812,1704,1171,721},[{6,147,117},{4,148,118}],4},
	{{'L',25},{3057,1853,1273,784},[{8,132,106},{4,133,107}],4},
	{{'L',26},{3283,1990,1367,842},[{10,142,114},{2,143,115}],4},
	{{'L',27},{3517,2132,1465,902},[{8,152,122},{4,153,123}],4},
	{{'L',28},{3669,2223,1528,940},[{3,147,117},{10,148,118}],3},
	{{'L',29},{3909,2369,1628,1002},[{7,146,116},{7,147,117}],3},
	{{'L',30},{4158,2520,1732,1066},[{5,145,115},{10,146,116}],3},
	{{'L',31},{4417,2677,1840,1132},[{13,145,115},{3,146,116}],3},
	{{'L',32},{4686,2840,1952,1201},[{17,145,115}],3},
	{{'L',33},{4965,3009,2068,1273},[{17,145,115},{1,146,116}],3},
	{{'L',34},{5253,3183,2188,1347},[{13,145,115},{6,146,116}],3},
	{{'L',35},{5529,3351,2303,1417},[{12,151,121},{7,152,122}],0},
	{{'L',36},{5836,3537,2431,1496},[{6,151,121},{14,152,122}],0},
	{{'L',37},{6153,3729,2563,1577},[{17,152,122},{4,153,123}],0},
	{{'L',38},{6479,3927,2699,1661},[{4,152,122},{18,153,123}],0},
	{{'L',39},{6743,4087,2809,1729},[{20,147,117},{4,148,118}],0},
	{{'L',40},{7089,4296,2953,1817},[{19,148,118},{6,149,119}],0},
	{{'M',1},{34,20,14,8},[{1,26,16}],0},
	{{'M',2},{63,38,26,16},[{1,44,28}],7},
	{{'M',3},{101,61,42,26},[{1,70,44}],7},
	{{'M',4},{149,90,62,38},[{2,50,32}],7},
	{{'M',5},{202,122,84,52},[{2,67,43}],7},
	{{'M',6},{255,154,106,65},[{4,43,27}],7},
	{{'M',7},{293,178,122,75},[{4,49,31}],0},
	{{'M',8},{365,221,152,93},[{2,60,38},{2,61,39}],0},
	{{'M',9},{432,262,180,111},[{3,58,36},{2,59,37}],0},
	{{'M',10},{513,311,213,131},[{4,69,43},{1,70,44}],0},
	{{'M',11},{604,366,251,155},[{1,80,50},{4,81,51}],0},
	{{'M',12},{691,419,287,177},[{6,58,36},{2,59,37}],0},
	{{'M',13},{796,483,331,204},[{8,59,37},{1,60,38}],0},
	{{'M',14},{871,528,362,223},[{4,64,40},{5,65,41}],3},
	{{'M',15},{991,600,412,254},[{5,65,41},{5,66,42}],3},
	{{'M',16},{1082,656,450,277},[{7,73,45},{3,74,46}],3},
	{{'M',17},{1212,734,504,310},[{10,74,46},{1,75,47}],3},
	{{'M',18},{1346,816,560,345},[{9,69,43},{4,70,44}],3},
	{{'M',19},{1500,909,624,384},[{3,70,44},{11,71,45}],3},
	{{'M',20},{1600,970,666,410},[{3,67,41},{13,68,42}],3},
	{{'M',21},{1708,1035,711,438},[{17,68,42}],4},
	{{'M',22},{1872,1134,779,480},[{17,74,46}],4},
	{{'M',23},{2059,1248,857,528},[{4,75,47},{14,76,48}],4},
	{{'M',24},{2188,1326,911,561},[{6,73,45},{14,74,46}],4},
	{{'M',25},{2395,1451,997,614},[{8,75,47},{13,76,48}],4},
	{{'M',26},{2544,1542,1059,652},[{19,74,46},{4,75,47}],4},
	{{'M',27},{2701,1637,1125,692},[{22,73,45},{3,74,46}],4},
	{{'M',28},{2857,1732,1190,732},[{3,73,45},{23,74,46}],3},
	{{'M',29},{3035,1839,1264,778},[{21,73,45},{7,74,46}],3},
	{{'M',30},{3289,1994,1370,843},[{19,75,47},{10,76,48}],3},
	{{'M',31},{3486,2113,1452,894},[{2,74,46},{29,75,47}],3},
	{{'M',32},{3693,2238,1538,947},[{10,74,46},{23,75,47}],3},
	{{'M',33},{3909,2369,1628,1002},[{14,74,46},{21,75,47}],3},
	{{'M',34},{4134,2506,1722,1060},[{14,74,46},{23,75,47}],3},
	{{'M',35},{4343,2632,1809,1113},[{12,75,47},{26,76,48}],0},
	{{'M',36},{4588,2780,1911,1176},[{6,75,47},{34,76,48}],0},
	{{'M',37},{4775,2894,1989,1224},[{29,74,46},{14,75,47}],0},
	{{'M',38},{5039,3054,2099,1292},[{13,74,46},{32,75,47}],0},
	{{'M',39},{5313,3220,2213,1362},[{40,75,47},{7,76,48}],0},
	{{'M',40},{5596,3391,2331,1435},[{18,75,47},{31,76,48}],0},
	{{'Q',1},{27,16,11,7},[{1,26,13}],0},
	{{'Q',2},{48,29,20,12},[{1,44,22}],7},
	{{'Q',3},{77,47,32,20},[{2,35,17}],7},
	{{'Q',4},{111,67,46,28},[{2,50,24}],7},
	{{'Q',5},{144,87,60,37},[{2,33,15},{2,34,16}],7},
	{{'Q',6},{178,108,74,45},[{4,43,19}],7},
	{{'Q',7},{207,125,86,53},[{2,32,14},{4,33,15}],0},
	{{'Q',8},{259,157,108,66},[{4,40,18},{2,41,19}],0},
	{{'Q',9},{312,189,130,80},[{4,36,16},{4,37,17}],0},
	{{'Q',10},{364,221,151,93},[{6,43,19},{2,44,20}],0},
	{{'Q',11},{427,259,177,109},[{4,50,22},{4,51,23}],0},
	{{'Q',12},{489,296,203,125},[{4,46,20},{6,47,21}],0},
	{{'Q',13},{580,352,241,149},[{8,44,20},{4,45,21}],0},
	{{'Q',14},{621,376,258,159},[{11,36,16},{5,37,17}],3},
	{{'Q',15},{703,426,292,180},[{5,54,24},{7,55,25}],3},
	{{'Q',16},{775,470,322,198},[{15,43,19},{2,44,20}],3},
	{{'Q',17},{876,531,364,224},[{1,50,22},{15,51,23}],3},
	{{'Q',18},{948,574,394,243},[{17,50,22},{1,51,23}],3},
	{{'Q',19},{1063,644,442,272},[{17,47,21},{4,48,22}],3},
	{{'Q',20},{1159,702,482,297},[{15,54,24},{5,55,25}],3},
	{{'Q',21},{1224,742,509,314},[{17,50,22},{6,51,23}],4},
	{{'Q',22},{1358,823,565,348},[{7,54,24},{16,55,25}],4},
	{{'Q',23},{1468,890,611,376},[{11,54,24},{14,55,25}],4},
	{{'Q',24},{1588,963,661,407},[{11,54,24},{16,55,25}],4},
	{{'Q',25},{1718,1041,715,440},[{7,54,24},{22,55,25}],4},
	{{'Q',26},{1804,1094,751,462},[{28,50,22},{6,51,23}],4},
	{{'Q',27},{1933,1172,805,496},[{8,53,23},{26,54,24}],4},
	{{'Q',28},{2085,1263,868,534},[{4,54,24},{31,55,25}],3},
	{{'Q',29},{2181,1322,908,559},[{1,53,23},{37,54,24}],3},
	{{'Q',30},{2358,1429,982,604},[{15,54,24},{25,55,25}],3},
	{{'Q',31},{2473,1499,1030,634},[{42,54,24},{1,55,25}],3},
	{{'Q',32},{2670,1618,1112,684},[{10,54,24},{35,55,25}],3},
	{{'Q',33},{2805,1700,1168,719},[{29,54,24},{19,55,25}],3},
	{{'Q',34},{2949,1787,1228,756},[{44,54,24},{7,55,25}],3},
	{{'Q',35},{3081,1867,1283,790},[{39,54,24},{14,55,25}],0},
	{{'Q',36},{3244,1966,1351,832},[{46,54,24},{10,55,25}],0},
	{{'Q',37},{3417,2071,1423,876},[{49,54,24},{10,55,25}],0},
	{{'Q',38},{3599,2181,1499,923},[{48,54,24},{14,55,25}],0},
	{{'Q',39},{3791,2298,1579,972},[{43,54,24},{22,55,25}],0},
	{{'Q',40},{3993,2420,1663,1024},[{34,54,24},{34,55,25}],0},
	{{'H',1},{17,10,7,4},[{1,26,9}],0},
	{{'H',2},{34,20,14,8},[{1,44,16}],7},
	{{'H',3},{58,35,24,15},[{2,35,13}],7},
	{{'H',4},{82,50,34,21},[{4,25,9}],7},
	{{'H',5},{106,64,44,27},[{2,33,11},{2,34,12}],7},
	{{'H',6},{139,84,58,36},[{4,43,15}],7},
	{{'H',7},{154,93,64,39},[{4,39,13},{1,40,14}],0},
	{{'H',8},{202,122,84,52},[{4,40,14},{2,41,15}],0},
	{{'H',9},{235,143,98,60},[{4,36,12},{4,37,13}],0},
	{{'H',10},{288,174,119,74},[{6,43,15},{2,44,16}],0},
	{{'H',11},{331,200,137,85},[{3,36,12},{8,37,13}],0},
	{{'H',12},{374,227,155,96},[{7,42,14},{4,43,15}],0},
	{{'H',13},{427,259,177,109},[{12,33,11},{4,34,12}],0},
	{{'H',14},{468,283,194,120},[{11,36,12},{5,37,13}],3},
	{{'H',15},{530,321,220,136},[{11,36,12},{7,37,13}],3},
	{{'H',16},{602,365,250,154},[{3,45,15},{13,46,16}],3},
	{{'H',17},{674,408,280,173},[{2,42,14},{17,43,15}],3},
	{{'H',18},{746,452,310,191},[{2,42,14},{19,43,15}],3},
	{{'H',19},{813,493,338,208},[{9,39,13},{16,40,14}],3},
	{{'H',20},{919,557,382,235},[{15,43,15},{10,44,16}],3},
	{{'H',21},{969,587,403,248},[{19,46,16},{6,47,17}],4},
	{{'H',22},{1056,640,439,270},[{34,37,13}],4},
	{{'H',23},{1108,672,461,284},[{16,45,15},{14,46,16}],4},
	{{'H',24},{1228,744,511,315},[{30,46,16},{2,47,17}],4},
	{{'H',25},{1286,779,535,330},[{22,45,15},{13,46,16}],4},
	{{'H',26},{1425,864,593,365},[{33,46,16},{4,47,17}],4},
	{{'H',27},{1501,910,625,385},[{12,45,15},{28,46,16}],4},
	{{'H',28},{1581,958,658,405},[{11,45,15},{31,46,16}],3},
	{{'H',29},{1677,1016,698,430},[{19,45,15},{26,46,16}],3},
	{{'H',30},{1782,1080,742,457},[{23,45,15},{25,46,16}],3},
	{{'H',31},{1897,1150,790,486},[{23,45,15},{28,46,16}],3},
	{{'H',32},{2022,1226,842,518},[{19,45,15},{35,46,16}],3},
	{{'H',33},{2157,1307,898,553},[{11,45,15},{46,46,16}],3},
	{{'H',34},{2301,1394,958,590},[{59,46,16},{1,47,17}],3},
	{{'H',35},{2361,1431,983,605},[{22,45,15},{41,46,16}],0},
	{{'H',36},{2524,1530,1051,647},[{2,45,15},{64,46,16}],0},
	{{'H',37},{2625,1591,1093,673},[{24,45,15},{46,46,16}],0},
	{{'H',38},{2735,1658,1139,701},[{42,45,15},{32,46,16}],0},
	{{'H',39},{2927,1774,1219,750},[{10,45,15},{67,46,16}],0},
	{{'H',40},{3057,1852,1273,784},[{20,45,15},{61,46,16}],0}
]).


-define(FINDER_BITS, <<6240274796270654599595212063015969838585429452563217548030:192>>).



decode(_Bin) ->
	{error, nyi}.


encode(Bin) ->
	encode(Bin, 'M').


encode(Bin, ECC) when is_binary(Bin) ->
	Params = choose_qr_params(Bin, ECC),
	Content = encode_content(Params, Bin),
	BlocksWithECC = generate_ecc_blocks(Params, Content),
	Codewords = interleave_blocks(BlocksWithECC),
	Matrix = matrix_embed_data(Params, Codewords),
	MaskedMatrices = generate_mask(Params, Matrix),
	Candidates = [matrix_overlay_static(Params, M) || M <- MaskedMatrices],
	{MaskType, SelectedMatrix} = select_mask(Candidates),
	Params0 = Params#qr_params{mask = MaskType},
	FMT = format_info_bits(Params0),
	VSN = version_info_bits(Params0),
	#qr_params{version = Version, dimension = Dim, ec_level = _ECC} = Params0,
	QRCode = matrix_finalize(Dim, FMT, VSN, ?QUIET_ZONE, SelectedMatrix),
	%% NOTE: Added "API" record
	#qrcode{version = Version, ecc = ECC, dimension = Dim + ?QUIET_ZONE * 2, data = QRCode}.


encode_png(Bin) ->
    #qrcode{dimension = Dim, data = Data} = encode(Bin),
	MAGIC = <<137, 80, 78, 71, 13, 10, 26, 10>>,
	Size = Dim * 8,
	IHDR = png_chunk(<<"IHDR">>, <<Size:32, Size:32, 8:8, 2:8, 0:24>>),
	PixelData = get_pixel_data(Dim, Data),
	IDAT = png_chunk(<<"IDAT">>, PixelData),
	IEND = png_chunk(<<"IEND">>, <<>>),
	<<MAGIC/binary, IHDR/binary, IDAT/binary, IEND/binary>>.


encode_png(Path, Bin) ->
    PNG = encode_png(Bin),
    file:write_file(Path, PNG).

png_chunk(Type, Bin) ->
	Length = byte_size(Bin),
	CRC = erlang:crc32(<<Type/binary, Bin/binary>>),
	<<Length:32, Type/binary, Bin/binary, CRC:32>>.

get_pixel_data(Dim, Data) ->
	Pixels = get_pixels(Data, 0, Dim, <<>>),
	zlib:compress(Pixels).

get_pixels(<<>>, Dim, Dim, Acc) ->
	Acc;
get_pixels(Bin, Count, Dim, Acc) ->
	<<RowBits:Dim/bits, Bits/bits>> = Bin,
	Row = get_pixels0(RowBits, <<0>>), % row filter byte
	FullRow = binary:copy(Row, 8),
	get_pixels(Bits, Count + 1, Dim, <<Acc/binary, FullRow/binary>>).

get_pixels0(<<1:1, Bits/bits>>, Acc) ->
	Black = binary:copy(<<0>>, 24),
	get_pixels0(Bits, <<Acc/binary, Black/binary>>);
get_pixels0(<<0:1, Bits/bits>>, Acc) ->
	White = binary:copy(<<255>>, 24),
	get_pixels0(Bits, <<Acc/binary, White/binary>>);
get_pixels0(<<>>, Acc) ->
	Acc.


choose_qr_params(Bin, ECLevel) ->
	Mode = choose_encoding(Bin),
	{Mode, Version, ECCBlockDefs, Remainder} = choose_version(Mode, ECLevel, byte_size(Bin)),
	AlignmentCoords = alignment_patterns(Version),
	Dim = matrix_dimension(Version),
	#qr_params{mode = Mode, version = Version, dimension = Dim, ec_level = ECLevel,
		block_defs = ECCBlockDefs, align_coords = AlignmentCoords, remainder = Remainder, data = Bin}.

%% NOTE: byte mode only (others removed)
choose_encoding(_Bin) ->
	byte.


choose_version(Type, ECC, Length) ->
	choose_version(Type, ECC, Length, ?TABLES).

choose_version(byte, ECC, Length, [{{ECC, Version}, {_, _, Capacity, _}, ECCBlocks, Remainder}|_])
		when Capacity >= Length ->
	{byte, Version, ECCBlocks, Remainder};
choose_version(Type, ECC, Length, [_|T]) ->
	choose_version(Type, ECC, Length, T).


encode_content(#qr_params{mode = Mode, version = Version}, Bin) ->
	encode_content(Mode, Version, Bin).

encode_content(byte, Version, Bin) ->
	encode_bytes(Version, Bin).


generate_ecc_blocks(#qr_params{block_defs = ECCBlockDefs}, Bin) ->
	Bin0 = pad_data(Bin, ECCBlockDefs),
	generate_ecc(Bin0, ECCBlockDefs, []).


pad_data(Bin, ECCBlockDefs) ->
	DataSize = byte_size(Bin),
	TotalSize = get_ecc_size(ECCBlockDefs),
	PaddingSize = TotalSize - DataSize,
	Padding = binary:copy(<<?DATA_PAD_0, ?DATA_PAD_1>>, PaddingSize bsr 1),
	case PaddingSize band 1 of
	0 ->
		<<Bin/binary, Padding/binary>>;
	1 ->
		<<Bin/binary, Padding/binary, ?DATA_PAD_0>>
	end.


get_ecc_size(ECCBlockDefs) ->
	get_ecc_size(ECCBlockDefs, 0).
get_ecc_size([{C, _, D}|T], Acc) ->
	get_ecc_size(T, C * D + Acc);
get_ecc_size([], Acc) ->
	Acc.


generate_ecc(Bin, [{C, L, D}|T], Acc) ->
	{Result, Bin0} = generate_ecc0(Bin, C, L, D, []),
	generate_ecc(Bin0, T, [Result|Acc]);
generate_ecc(<<>>, [], Acc) ->
	lists:flatten(lists:reverse(Acc)).


generate_ecc0(Bin, Count, TotalLength, BlockLength, Acc)
        when byte_size(Bin) >= BlockLength, Count > 0 ->
	<<Block:BlockLength/binary, Bin0/binary>> = Bin,
	EC = encode_rs(Block, TotalLength - BlockLength),
	generate_ecc0(Bin0, Count - 1, TotalLength, BlockLength, [{Block, EC}|Acc]);
generate_ecc0(Bin, 0, _, _, Acc) ->
	{lists:reverse(Acc), Bin}.


interleave_blocks(Blocks) ->
	Data = interleave_data(Blocks, <<>>),
	interleave_ecc(Blocks, Data).

interleave_data(Blocks, Bin) ->
	Data = [X || {X, _} <- Blocks],
	interleave_blocks(Data, [], Bin).

interleave_ecc(Blocks, Bin) ->
	Data = [X || {_, X} <- Blocks],
	interleave_blocks(Data, [], Bin).

interleave_blocks([], [], Bin) ->
	Bin;
interleave_blocks([], Acc, Bin) ->
	Acc0 = [X || X <- Acc, X =/= <<>>],
	interleave_blocks(lists:reverse(Acc0), [], Bin);
interleave_blocks([<<X, Data/binary>>|T], Acc, Bin) ->
	interleave_blocks(T, [Data|Acc], <<Bin/binary, X>>).


encode_bytes(Version, Bin) when is_binary(Bin) ->
	Size = size(Bin),
	CharacterCountBitSize = cci(?BYTE_MODE, Version),
	<<?BYTE_MODE:4, Size:CharacterCountBitSize, Bin/binary, 0:4>>.


%% Table 25. Error correction level indicators
ecc('L') -> 1;
ecc('M') -> 0;
ecc('Q') -> 3;
ecc('H') -> 2.

% Table 5. Charset encoder
% NOTE: removed

%%
alignment_patterns(Version) ->
	D = matrix_dimension(Version),
	L = element(Version, ?ALIGNMENT_COORDINATES),
	L0 = [{X, Y} || X <- L, Y <- L],
	L1 = [{X, Y} || {X, Y} <- L0, is_finder_region(D, X, Y) =:= false],
	% Change the natural sort order so that rows have greater weight than columns
	F = fun
		({_, Y}, {_, Y0}) when Y < Y0 ->
			true;
		({X, Y}, {X0, Y0}) when Y =:= Y0 andalso X =< X0 ->
			true;
		(_, _) ->
			false
		end,
	lists:sort(F, L1).

is_finder_region(D, X, Y)
		when (X =< 8 andalso Y =< 8)
		orelse (X =< 8 andalso Y >= D - 8)
		orelse (X >= D - 8 andalso Y =< 8) ->
	true;
is_finder_region(_, _, _) ->
	false.

%% Table 3. Number of bits in Character Count Indicator
cci(Mode, Version) when Version >= 1 andalso Version =< 40->
	{Mode, CC} = lists:keyfind(Mode, 1, ?CCI_BITSIZE),
	cci0(CC, Version).

cci0([X, _, _], Version) when Version =< 9 ->
	X;
cci0([_, X, _], Version) when Version =< 26 ->
	X;
cci0([_, _, X], _) ->
	X.

version_info_bits(#qr_params{version = Version}) when Version < 7 ->
	<<>>;
version_info_bits(#qr_params{version = Version}) when Version =< 40 ->
	BCH = bch_code_rs(Version, ?VERSION_INFO_POLY),
	<<Version:6, BCH:12>>.

format_info_bits(#qr_params{ec_level = ECLevel, mask = MaskType}) ->
	Info = (ecc(ECLevel) bsl 3) bor MaskType,
	BCH = bch_code_rs(Info, ?FORMAT_INFO_POLY),
	InfoWithEC = (Info bsl 10) bor BCH,
	Value = InfoWithEC bxor ?FORMAT_INFO_MASK,
	<<Value:15>>.


%%% Matrix Operations

matrix_dimension(Version) 
		when Version > 0 
		andalso Version < 41 ->
	17 + (Version * 4).


matrix_embed_data(#qr_params{version = Version, align_coords = AC, remainder = Rem}, Codewords) ->
	FlippedTemplate = flip(template(Version, AC)),
	FlippedMatrix = embed_data(FlippedTemplate, <<Codewords/binary, 0:Rem>>, []),
	flip(FlippedMatrix).
	

matrix_overlay_static(#qr_params{version = Version, align_coords = AC}, Matrix) ->
	F = finder_bits(),
	T = timing_bits(Version, AC),
	A = alignment_bits(AC),
	overlay_static(Matrix, F, T, A, []).


matrix_finalize(Dim, FMT, VSN, QZ, Matrix) ->
	M = format_bits(FMT),
	V = version_bits(VSN),
	FinalMatrix = overlay_format(Matrix, M, V, []),
	QBitLength = (Dim + QZ * 2) * QZ,
	Q = <<0:QBitLength>>,
	Bin = encode_bits(FinalMatrix, QZ, Q),
	<<Bin/bits, Q/bits>>.


template(Version, AC) ->
	Dim = matrix_dimension(Version),
	template(1, Dim, AC, []).

template(Y, Max, AC, Acc) when Y =< Max->
	Row = template_row(1, Y, Max, AC, []),
	template(Y + 1, Max, AC, [Row|Acc]);
template(_, _, _, Acc) ->
	lists:reverse(Acc).

template_row(X, Y, Max, AC, Acc) when X =< Max ->
	Ref = template_ref(X, Y, Max, AC),
	template_row(X + 1, Y, Max, AC, [Ref|Acc]);
template_row(_, _, _, _, Acc) ->
	lists:reverse(Acc).

template_ref(X, Y, Max, _AC) 
		when (X =< 8 andalso Y =< 8)
		orelse (X =< 8 andalso Y > Max - 8)
		orelse (X > Max - 8 andalso Y =< 8) ->
	f;
template_ref(X, Y, Max, _AC) 
		when (X =:= 9 andalso Y =/= 7 andalso (Y =< 9 orelse Max - Y =< 7))
		orelse (Y =:= 9 andalso X =/= 7 andalso (X =< 9 orelse Max - X =< 7)) ->
	m;
template_ref(X, Y, Max, _AC) 
		when Max >= 45 
		andalso ((X < 7 andalso Max - Y =< 10) 
		orelse (Max - X =< 10 andalso Y < 7)) ->
	v;
template_ref(X, Y, Max, AC) ->
	case is_alignment_bit(X, Y, AC) of
	true -> 
		a;
	false ->
		template_ref0(X, Y, Max)
	end.

template_ref0(X, Y, _)
		when X =:= 7 
		orelse Y =:= 7 ->
	t;
template_ref0(_, _, _) ->
	d.


is_alignment_bit(X, Y, [{Xa, Ya}|_]) 
		when (X >= Xa - 2 
		andalso X =< Xa + 2 
		andalso Y >= Ya - 2 
		andalso Y =< Ya + 2) ->
	true;
is_alignment_bit(X, Y, [_|T]) ->
	is_alignment_bit(X, Y, T);
is_alignment_bit(_X, _Y, []) ->
	false.
	
% deal with row 7 exceptional case
embed_data([HA, HB, H, HC, HD|T], Codewords, Acc) when length(T) =:= 4 -> % skip row 7
	{HA0, HB0, Codewords0} = embed_data(HA, HB, Codewords, [], []),	
	{HC0, HD0, Codewords1} = embed_data_reversed(HC, HD, Codewords0),	
	embed_data(T, Codewords1, [HD0, HC0, H, HB0, HA0|Acc]);
% normal case
embed_data([HA, HB, HC, HD|T], Codewords, Acc) ->
	{HA0, HB0, Codewords0} = embed_data(HA, HB, Codewords, [], []),	
	{HC0, HD0, Codewords1} = embed_data_reversed(HC, HD, Codewords0),	
	embed_data(T, Codewords1, [HD0, HC0, HB0, HA0|Acc]);
embed_data([], <<>>, Acc) ->
	lists:reverse(Acc).
	
embed_data([d|T0], [d|T1], <<A:1, B:1, Codewords/bits>>, StreamA, StreamB) ->
	embed_data(T0, T1, Codewords, [A|StreamA], [B|StreamB]);
embed_data([d|T0], [B|T1], <<A:1, Codewords/bits>>, StreamA, StreamB) ->
	embed_data(T0, T1, Codewords, [A|StreamA], [B|StreamB]);
embed_data([A|T0], [d|T1], <<B:1, Codewords/bits>>, StreamA, StreamB) ->
	embed_data(T0, T1, Codewords, [A|StreamA], [B|StreamB]);
embed_data([A|T0], [B|T1], Codewords, StreamA, StreamB) ->
	embed_data(T0, T1, Codewords, [A|StreamA], [B|StreamB]);
embed_data([], [], Codewords, StreamA, StreamB) ->
	{lists:reverse(StreamA), lists:reverse(StreamB), Codewords}.
	
embed_data_reversed(A, B, Codewords) ->
	{A0, B0, Codewords0} = embed_data(lists:reverse(A), lists:reverse(B), Codewords, [], []),
	{lists:reverse(A0), lists:reverse(B0), Codewords0}.


overlay_static([H|L], F, T, A, Acc) ->
	{F0, T0, A0, Row} = overlay0(H, F, T, A, []),
	overlay_static(L, F0, T0, A0, [Row|Acc]);
overlay_static([], <<>>, <<>>, <<>>, Acc) ->
	lists:reverse(Acc).

overlay0([f|L], <<F0:1, F/bits>>, T, A, Acc) ->
	overlay0(L, F, T, A, [F0|Acc]);	
overlay0([t|L], F, <<T0:1, T/bits>>, A, Acc) ->
	overlay0(L, F, T, A, [T0|Acc]);
overlay0([a|L], F, T, <<A0:1, A/bits>>, Acc) ->
	overlay0(L, F, T, A, [A0|Acc]);
overlay0([H|L], F, T, A, Acc) ->
	overlay0(L, F, T, A, [H|Acc]);
overlay0([], F, T, A, Acc) ->
	{F, T, A, lists:reverse(Acc)}.


encode_bits([H|T], QZ, Acc) ->
	Acc0 = encode_bits0(H, <<Acc/bits, 0:QZ>>),
	encode_bits(T, QZ, <<Acc0/bits, 0:QZ>>);
encode_bits([], _, Acc) ->
	Acc.
	
encode_bits0([H|T], Acc) when is_integer(H) ->
	encode_bits0(T, <<Acc/bits, H:1>>);
encode_bits0([], Acc) ->
	Acc.

overlay_format([H|L], M, V, Acc) ->
	{M0, V0, Row} = overlay1(H, M, V, []),
	overlay_format(L, M0, V0, [Row|Acc]);
overlay_format([], <<>>, <<>>, Acc) ->
	lists:reverse(Acc).

overlay1([m|L], <<M0:1, M/bits>>, V, Acc) ->
	overlay1(L, M, V, [M0|Acc]);	
overlay1([v|L], M, <<V0:1, V/bits>>, Acc) ->
	overlay1(L, M, V, [V0|Acc]);
overlay1([H|L], M, V, Acc) ->
	overlay1(L, M, V, [H|Acc]);
overlay1([], M, V, Acc) ->
	{M, V, lists:reverse(Acc)}.


flip(L) ->
	flip(L, []).
flip([[]|T], Acc) ->
	[[] || [] <- T], % guard check
	[lists:reverse(L) || L <- Acc];
flip(L, Acc) ->
	Heads = [H || [H|_] <- L],
	Tails = [T || [_|T] <- L],
	flip(Tails, [Heads|Acc]).


finder_bits() ->
	?FINDER_BITS.

alignment_bits(AC) ->
	Repeats = composite_ac(AC, []),
	alignment_bits(Repeats, <<>>).
alignment_bits([H|T], Acc) ->
	Bits0 = bit_duplicate(<<31:5>>, H),
	Bits1 = bit_duplicate(<<17:5>>, H),
	Bits2 = bit_duplicate(<<21:5>>, H),
	Bits = bit_append([Bits0, Bits1, Bits2, Bits1, Bits0]),
	alignment_bits(T, <<Acc/bits, Bits/bits>>);
alignment_bits([], Acc) ->
	Acc.

composite_ac([{_, Row}|T], Acc) ->
	N = 1 + length([{X, Y} || {X, Y} <- T, Y =:= Row]),
	T0 = [{X, Y} || {X, Y} <- T, Y =/= Row],
	composite_ac(T0, [N|Acc]);
composite_ac([], Acc) ->
	lists:reverse(Acc).


timing_bits(Version, AC) ->
	Length = matrix_dimension(Version) - 16,
	% alignment pattern start coordinates, to trigger bit skipping
	TH = timing_bits(1, Length, [X - 8 - 2 || {X, 7} <- AC], <<>>),
	TV = timing_bits(1, Length, [Y - 8 - 2 || {7, Y} <- AC], <<>>),
	<<TH/bits, TV/bits>>.

timing_bits(N, Max, A, Acc) when N =< Max ->
	case lists:member(N, A) of
	true -> % skip the alignment pattern
		timing_bits(N + 5, Max, A, Acc);
	false ->
		Bit = N band 1,
		timing_bits(N + 1, Max, A, <<Acc/bits, Bit:1>>)
	end;
timing_bits(_, _, _, Acc) ->
	Acc.


format_bits(Bin) ->
	<<A:7, C:1, E:7>> = bit_reverse(Bin),
	<<B:8, D:7>> = Bin,
	<<A:7, B:8, C:1, D:7, 1:1, E:7>>.


version_bits(Bin) ->
	VTop = bit_reverse(Bin),
	VLeft = version_bits(VTop, []),
	<<VTop/bits, VLeft/bits>>.

version_bits(<<X:3/bits, Bin/bits>>, Acc) ->
	version_bits(Bin, [X|Acc]);
version_bits(<<>>, Acc) ->
	version_bits(lists:reverse(Acc), <<>>, <<>>, <<>>).

version_bits([<<A:1, B:1, C:1>>|T], RowA, RowB, RowC) ->
	version_bits(T, <<RowA/bits, A:1>>, <<RowB/bits, B:1>>, <<RowC/bits, C:1>>);
version_bits([], RowA, RowB, RowC) ->
	bit_append([RowA, RowB, RowC]).



%%% Mask operations

-define(PENALTY_RULE_1, 3).
-define(PENALTY_RULE_2, 3).
-define(PENALTY_RULE_3, 40).
-define(PENALTY_RULE_4, 10).

%% Generates all eight masked versions of the bit matrix
generate_mask(#qr_params{dimension = Dim}, Matrix) ->
	Sequence = lists:seq(0, 7),
	Functions = [mask(X) || X <- Sequence],
	Masks = [generate_mask2(Dim, MF) || MF <- Functions],
	[apply_mask(Matrix, Mask, []) || Mask <- Masks].
	
%% Selects the lowest penalty candidate from a list of bit matrices
select_mask([H|T]) ->
	Score = score_candidate(H),
	select_candidate(T, 0, 0, Score, H).


generate_mask2(Max, MF) ->
	Sequence = lists:seq(0, Max - 1),
	[generate_mask2(Sequence, Y, MF) || Y <- Sequence].
generate_mask2(Sequence, Y, MF) ->
	[case MF(X, Y) of true -> 1; false -> 0 end || X <- Sequence].

apply_mask([H|T], [H0|T0], Acc) ->
	Row = apply_mask0(H, H0, []),
	apply_mask(T, T0, [Row|Acc]);
apply_mask([], [], Acc) ->
	lists:reverse(Acc).
	
apply_mask0([H|T], [H0|T0], Acc) when is_integer(H) ->
	apply_mask0(T, T0, [H bxor H0|Acc]);
apply_mask0([H|T], [_|T0], Acc) ->
	apply_mask0(T, T0, [H|Acc]);
apply_mask0([], [], Acc) ->
	lists:reverse(Acc).

% (i + j) mod 2 = 0
mask(0) -> 
	fun(X, Y) -> (X + Y) rem 2 =:= 0 end;
% i mod 2 = 0
mask(1) -> 
	fun(_X, Y) -> Y rem 2 =:= 0 end;
% j mod 3 = 0
mask(2) -> 
	fun(X, _Y) -> X rem 3 =:= 0 end;
% (i + j) mod 3 = 0
mask(3) -> 
	fun(X, Y) -> (X + Y) rem 3 =:= 0 end;
% ((i div 2) + (j div 3)) mod 2 = 0
mask(4) -> 
	fun(X, Y) -> (X div 3 + Y div 2) rem 2 =:= 0 end;
%101 (i * j) mod 2 + (i *j) mod 3 = 0
mask(5) -> 
	fun(X, Y) -> Sum = X * Y, Sum rem 2 + Sum rem 3 =:= 0 end;
% ((i * j) mod 2 + (i* j) mod 3) mod 2 = 0
mask(6) -> 
	fun(X, Y) -> Sum = X * Y, (Sum rem 2 + Sum rem 3) rem 2 =:= 0 end;
%((i * j) mod 3 + (i + j) mod 2) mod 2 = 0
mask(7) -> 
	fun(X, Y) -> ((X * Y rem 3) + ((X + Y) rem 2)) rem 2 =:= 0 end.
	
select_candidate([H|T], Count, Mask, Score, C) ->
	case score_candidate(H) of
	X when X < Score ->
		select_candidate(T, Count + 1, Count + 1, X, H);
	_ ->
		select_candidate(T, Count + 1, Mask, Score, C)
	end;
select_candidate([], _, Mask, _Score, C) ->
	{Mask, C}.

score_candidate(C) ->
	Rule1 = apply_penalty_rule_1(C),
	Rule2 = apply_penalty_rule_2(C),
	Rule3 = apply_penalty_rule_3(C),
	Rule4 = apply_penalty_rule_4(C),
	Rule1 + Rule2 + Rule3 + Rule4.
	
%% Section 8.2.2
apply_penalty_rule_1(Candidate) ->
	ScoreRows = rule1(Candidate, 0),
	ScoreCols = rule1(rows_to_columns(Candidate), 0),
	ScoreRows + ScoreCols.

rule1([Row|T], Score) ->
	Score0 = rule1_row(Row, Score),
	rule1(T, Score0);
rule1([], Score) ->
	Score.

rule1_row(L = [H|_], Score) ->
	F = fun
		(1) when H =:= 1 ->
			true;
		(1) ->
			false;
		(_) when H =:= 0 orelse is_integer(H) =:= false ->
			true;
		(_) ->
			false
		end,
	{H0,T0} = lists:splitwith(F, L),
	case length(H0) of 
	Repeats when Repeats >= 5 ->
		Penalty = ?PENALTY_RULE_1 + Repeats - 5,
		rule1_row(T0, Score + Penalty);
	_ ->
		rule1_row(T0, Score)
	end;
rule1_row([], Score) ->
	Score.


apply_penalty_rule_2(_M = [H, H0|T]) ->
	Blocks = rule2(1, 1, H, H0, [H0|T], []),
	Blocks0 = composite_blocks(Blocks, []),
	Blocks1 = composite_blocks(Blocks0, []),
	score_blocks(Blocks1, 0).

score_blocks([{_, {M, N}, _}|T], Acc) ->
	Score = ?PENALTY_RULE_2 * (M - 1) * (N - 1),
	score_blocks(T, Acc + Score);
score_blocks([], Acc) ->
	Acc.
	
rule2(X, Y, [H, H|T], [H, H|T0], Rows, Acc) ->
	rule2(X + 1, Y, [H|T], [H|T0], Rows, [{{X, Y}, {2, 2}, H}|Acc]);
rule2(X, Y, [_|T], [_|T0], Rows, Acc) ->
	rule2(X + 1, Y, T, T0, Rows, Acc);
rule2(_, Y, [], [], [H, H0|T], Acc) ->
	rule2(1, Y + 1, H, H0, [H0|T], Acc);
rule2(_, _, [], [], [_], Acc) ->
	lists:reverse(Acc).

composite_blocks([H|T], Acc) ->
	{H0, T0} = composite_block(H, T, []),
	composite_blocks(T0, [H0|Acc]);
composite_blocks([], Acc) ->
	lists:reverse(Acc).

composite_block(B, [H|T], Acc) ->
	case combine_block(B, H) of
	false ->
		composite_block(B, T, [H|Acc]);
	B0 ->
		composite_block(B0, T, Acc)
	end;
composite_block(B, [], Acc) ->
	{B, lists:reverse(Acc)}.

% Does Block 0 contain the Block 1 coordinate?
combine_block(B = {{X, Y}, {SX, SY}, _}, B0 = {{X0, Y0}, _, _}) 
		when X0 < X + SX orelse Y0 < Y + SY  ->
	combine_block0(B, B0);
combine_block(_, _) ->
	false.
	
% are they same valued?
combine_block0(B = {_, _, V}, B0 = {_, _, V0}) 
	when V =:= V0 orelse (V =/= 1 andalso V0 =/= 1) ->
	combine_block1(B, B0);
combine_block0(_, _) ->
	false.
	
% is B extended by B0 horizontally?
combine_block1({{X, Y}, {SX, SY}, V}, {{X0, Y}, {SX0, SY}, _}) when X0 =:= X + SX - 1 ->
	{{X, Y}, {SX + SX0 - 1, SY}, V};
% is B extended by B0 vertically?
combine_block1({{X, Y}, {SX, SY}, V}, {{X, Y0}, {SX, SY0}, _}) when Y0 =:= Y + SY - 1 ->
	{{X, Y}, {SX, SY + SY0 - 1}, V};
combine_block1(_, _) ->
	false.


apply_penalty_rule_3(Candidate) -> 
	RowScores = [rule3(Row, 0) || Row <- Candidate],
	ColumnScores = [rule3(Col, 0) || Col <- rows_to_columns(Candidate)],
	lists:sum(RowScores) + lists:sum(ColumnScores).

rule3(Row = [1|T], Score) ->
	Ones = lists:takewhile(fun(X) -> X =:= 1 end, Row),
	Scale = length(Ones),
	case Scale * 7 of
	Length when Length > length(Row) ->
		rule3(T, Score);
	Length ->
		case is_11311_pattern(lists:sublist(Row, Length), Scale) of
		true ->
			rule3(T, Score + ?PENALTY_RULE_3);
		false ->
			rule3(T, Score)
		end
	end;
rule3([_|T], Score) ->
	rule3(T, Score);
rule3([], Acc) ->
	Acc.

is_11311_pattern(List, Scale) ->
	List0 = lists:map(fun(X) when X =:= 1 -> 1; (_) -> 0 end, List), 
	Result = condense(List0, Scale, []),
	Result =:= [1,0,1,1,1,0,1].

condense([], _, Acc) ->
	lists:reverse(Acc);
condense(L, Scale, Acc) ->
	{H, T} = lists:split(Scale, L),
	case lists:sum(H) of
	Scale ->
		condense(T, Scale, [1|Acc]);
	0 ->
		condense(T, Scale, [0|Acc]);
	_ ->
		undefined
	end.
	

apply_penalty_rule_4(Candidate) ->
	Proportion = rule4(Candidate, 0, 0),
	?PENALTY_RULE_4 * (trunc(abs(Proportion * 100 - 50)) div 5).

rule4([H|T], Dark, All) ->
	All0 = All + length(H),
	Dark0 = Dark + length([X || X <- H, X =:= 1]),
	rule4(T, Dark0, All0);
rule4([], Dark, All) ->
	Dark / All.


rows_to_columns(L) ->
	rows_to_columns(L, []).
rows_to_columns([[]|_], Acc) ->
	lists:reverse(Acc);
rows_to_columns(L, Acc) ->
	Heads = [H || [H|_] <- L],
	Tails = [T || [_|T] <- L],
	rows_to_columns(Tails, [Heads|Acc]).


%%% Reed-Solomon Implementation

-define(QRCODE_GF256_PRIME_MODULUS, 285). % 16#011D = 2^8 + 2^4 + 2^3 + 2^2 + 2^0


encode_rs(Bin, Degree) when Degree > 0 ->
	Field = gf256:field(?QRCODE_GF256_PRIME_MODULUS),
	Generator = generator(Field, Degree),
	Data = binary_to_list(Bin),
	Coeffs = gf256:monomial_product(Field, Data, 1, Degree),
	{_Quotient, Remainder} = gf256:divide(Field, Coeffs, Generator),
	ErrorCorrectionBytes = list_to_binary(Remainder),
	<<ErrorCorrectionBytes/binary>>.


bch_code_rs(Byte, Poly) ->
	MSB = msb(Poly),
	Byte0 = Byte bsl (MSB - 1),
	bch_code(Byte0, Poly, MSB).


%% Internal


generator(F, D) when D > 0 ->
	generator(F, [1], D, 0).

generator(_, P, D, D) ->
	P;
generator(F, P, D, Count) ->
	P0 = gf256:polynomial_product(F, P, [1, gf256:exponent(F, Count)]),
	generator(F, P0, D, Count + 1).
	

bch_code(Byte, Poly, MSB) ->
	case msb(Byte) >= MSB of
	true ->
		Byte0 = Byte bxor (Poly bsl (msb(Byte) - MSB)),
		bch_code(Byte0, Poly, MSB);
	false ->
		Byte
	end.


msb(0) ->
	0;
msb(Byte) ->
	msb(Byte, 0).
msb(0, Count) ->
	Count;
msb(Byte, Count) ->
	msb(Byte bsr 1, Count + 1).


%%% The bits that twiddle bits

bit_reverse(Bin) ->
	bit_reverse(Bin, <<>>).
bit_reverse(<<X:1, Bin/bits>>, Acc) ->
	bit_reverse(Bin, <<X:1, Acc/bits>>);
bit_reverse(<<>>, Acc) ->
	Acc.


bit_duplicate(Bin, N) ->
	bit_duplicate(Bin, N, <<>>).
bit_duplicate(Bin, N, Acc) when N > 0 ->
	bit_duplicate(Bin, N - 1, <<Acc/bits, Bin/bits>>);
bit_duplicate(_, 0, Acc) ->
	Acc.


bit_append(List) ->
	bit_append(List, <<>>).
bit_append([H|T], Acc) ->
	bit_append(T, <<Acc/bits, H/bits>>);
bit_append([], Acc) ->
	Acc.
