libname Opt “/path/to/file”;

proc import datafile="/path/to/file/ATTRIBUTES.csv"
	out=att dbms=csv replace;
	getnames=yes;
run;

proc import datafile="/path/to/file/PROMO_LIFT.csv"
	out=lift dbms=csv replace;
	getnames=yes;
run;

proc import datafile="/path/to/file/PRODUCT_MASTER.csv"
	out=Master dbms=csv replace;
	getnames=yes;
run;


proc sort data=Lift ; by SKU; run;


proc sort data=att out=attSorted;
by SKU descending price_tier;
run;

proc sort data=master out=mastSorted;
by sku cost;
run;

data attSorted;
set attSorted;
counter + 1;
run;
data mastSorted;
set mastSorted;
counter + 1;
run;

proc sql;
create table products as
SELECT *
FROM attSorted, mastSorted
WHERE attSorted.counter = mastSorted.counter;
run;
quit;

proc sort data=products out=productSort;
	by SKU List_price ;
run;

data lift1 lift2 lift3;
	set lift;
	if PROMO = "BOGO" then output lift1;
	else if PROMO="20OF" then output lift2;
	else if PROMO="30OF" then output lift3;
run;

proc sort data=lift1 ; by SKU ; 
proc sort data=lift2 ; by SKU ; 
proc sort data=Lift3 ; by SKU ; run;

data ProfitNoPromo;
	set Products;
	ProfitNoPromo = Base_Demand*(List_Price - Cost);
run;

data Profit20;
	merge lift2 Products;
	by SKU;
	Price20=List_Price*.8;
	lift20=lift;
	profit20 = (Base_Demand*(1+lift))*(Price20 - Cost);
run;

data Profit30;
	merge lift3 Products;
	by SKU ;
	price30=List_Price*.7;
	lift30=lift;
	profit30 = (Base_Demand*(1+lift))*(Price30 - Cost);
run;

data ProfitBOGO;
	merge lift1 Products;
	by SKU ;
	Price50=List_price*.5;
	lift50=lift;
	profit50 = (Base_Demand*(1+lift))*(price50- Cost);
run;

data Profit;
	merge ProfitNoPromo Profit20 Profit30 ProfitBOGO;
	by SKU;
run;


/*-----------------------------------------*/

data products2;
set products;
output;
output;
run;
proc sort data=products2 out=products2sorted;
by SKU list_price;
run;
data products2sorted;
set products2sorted;
counter + 1;
run;

proc sort data=profit out=profitsorted;
by sku cost lift50 lift30 lift20;
run;
data profitsorted;
set profitsorted;
counter + 1;
run;

proc sql;
create table final AS
SELECT *
FROM products2sorted, profitsorted
WHERE products2sorted.counter = profitsorted.counter;
run;
quit;
data final;
set final;
drop counter;
run;

data final2;
set final;
ident = SKU || Brand;
run;

data final3;
	set final2;
	if mod(_N_,2) = 0 then Region_ID = 'SC';
	if mod(_N_,2) ne 0 then Region_ID = 'NC';
run;

data end (keep=Ident Promo Profit Region Price Tier);
set final3;
do i=1 to 4;
if i = 1 then do;
Ident = Ident;
Promo = 'None';
Profit = ProfitNoPromo;
Region = Region_ID;
Price = List_Price;
Tier = Price_Tier;
output;
end;
else if i = 2 then do;
Ident = Ident;
Promo = '20Promo';
Profit = Profit20;
Region = Region_ID;
Price = Price20;
Tier = Price_Tier;
output;
end;
else if i = 3 then do;
Ident = Ident;
Promo = '30Promo';
Profit = Profit30;
Region = Region_ID;
Price = Price30;
Tier = Price_Tier;
output;
end;
else if i = 4 then do;
Ident = Ident;
Promo = '50Promo';
Profit = Profit50;
Region = Region_ID;
Price = Price50;
Tier = Price_Tier;
output;
end;
end;
run;

quit;
proc optmodel;
/* Formulate */

/* Sets */
set <str> ITEMS;
read data end into ITEMS=[ident];

set <str> PROMO;
read data end into Promo=[Promo];

set <STR> BEST;
read data end (where=(TIER='Best')) into BEST=[ident];

set <STR> BETTER;
read data end (where=(TIER='Bett')) into BETTER=[ident];

set <STR> GOOD;
read data end (where=(TIER='Good')) into GOOD=[ident];

set <STR>REGION;
read data end into REGION=[Region];

var Assign{Items, Promo, Region} Binary;

num Price{ITEMS, Promo,Region};
read data end
	into [ident promo region] Price;

num profit{ITEMS, PROMO, Region};
read data end
 	into [ident promo region] profit;
 

/* ObjectiveFunction */

max MaxProfit = sum {i in Items, p in promo, R in Region} 
	profit[i,p,R]*Assign[i,p,R];

/* Constraints */

con NumPromo{i in items, r in region}:
	sum{p in promo} Assign[i,p,R] = 1;

con Tier1{B in Better, C in Good, R in region}:
	sum{p in promo} Price[C,p,R]*Assign[C,p,R] <= sum{p in promo} Price[B,p,R]*Assign[B,p,R];

con Tier2{B in Better, A in Best, R in region}:
	sum{p in promo} Price[B,p,R]*Assign[B,p,R] <= sum{p in promo} Price[A,p,R]*Assign[A,p,R];

con regionCon{i in Items}:
	sum{p in promo} Price[i,p,'SC']*Assign[i,p,'SC'] <= sum{p in promo} Price[i,p,'NC']*Assign[i,p,'NC'];

expand;
solve;

quit;
