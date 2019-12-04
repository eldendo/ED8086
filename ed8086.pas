(******************************************************************************
*  emulator for 8086/8088 subset as requested in                              *
* https://codegolf.stackexchange.com/questions/4732/emulate-an-intel-8086-cpu *
* (c)2019 by ir. Marc Dendooven                                               *
* V0.2 DEV                                                                    *
******************************************************************************) 
// there should be a test to prevent writeback to immediate.
// memory or register or immediate ???

// word/byte and reg/mem should be treated in access methods

// loopt tot printloop: (158)
 
program ed8086;
uses sysutils;

const showSub = 100;
//var dbug: boolean = true;

type 	nibble = 0..15;
		octed = 0..7;
		address = 0..$FFFF; // should be extended when using segmentation

const memSize = $9000; 
	  AX=0; CX=1; DX=2; BX=3; SP=4; BP=5; SI=6; DI=7;

type location = record
					memory: boolean; // memory or register
					aORi: address; // address or index to register
					content: word
				end;

var mem: array[0..memSize-1] of byte;
	IP,segEnd: word;
	IR: byte;
	mode: 0..3;
	sreg:0..7;
	rm:0..7;
	RX:array[AX..DI] of word; //AX,CX,DX,BX,SP,BP,SI,DI
	FC,FZ,FS: 0..1;
	cnt: cardinal = 0;
	d: 0..1;
	oper1,oper2: location;
	w: boolean; // is true when word / memory
	calldept: cardinal = 0;
  
	
// ---------------- general help methods ----------------
procedure display;
var x,y: smallint;
	c: byte;
begin
	writeln;
	for y := 0 to 24 do
		begin
		  for x := 0 to 79 do
			begin
				c := mem[$8000+y*80+x];
				if c=0 then write(' ') else write(char(c));
			end;
			writeln
		end
end;	

procedure error(s: string);
begin
	writeln;writeln;
	writeln('ERROR: ',s);
	writeln('program aborted');
	writeln;
	writeln('IP=',hexstr(IP,4),' IR=',hexstr(IR,2));
	display;
	halt
end;

procedure debug(s: string);
begin
	if CallDept < showSub then writeln(s)
end;

procedure load;
// load the codegolf binary at address 0
var	f,count: LongInt;
begin
	if not fileExists('codegolf') then error('file "codegolf" doesn''t exist in this directory');
	f := fileOpen('codegolf',fmOpenRead);
	count := fileRead(f,mem,memSize);
	fileClose(f);
	if count = -1 then error('Could not read file "codegolf"');
	writeln(count, ' bytes read to memory starting at 0');
	segEnd := count;
	writeln
end;

procedure mon;
begin
	if not (CallDept < showSub) then exit;
	writeln;
	writeln('------------- mon -------------');
	writeln('IP=',hexstr(IP,4));
	writeln('AX=',hexstr(RX[AX],4),' CX=',hexstr(RX[CX],4),' DX=',hexstr(RX[DX],4),' BX=',hexstr(RX[BX],4));
	writeln('SP=',hexstr(RX[SP],4),' BP=',hexstr(RX[BP],4),' SI=',hexstr(RX[SI],4),' DI=',hexstr(RX[DI],4));
	writeln('C=',FC,' Z=',FZ,' S=',FS);
	writeln('-------------------------------');
	writeln
//	writeln('push ENTER to continue');
//	readln
end;

// --------------- memory and register access ----------------
// memory should NEVER be accessed direct
// in order to intercept memory mapped IO
	
function peek(a:address):byte;
begin
	peek := mem[a]
end;

procedure poke(a:address;b:byte);
begin
	mem[a]:=b;
	case a of $8000..$87CF: 
		begin 
			writeln;
			writeln('*** a character has been written to the screen ! ***');
			writeln('''',chr(b),''' to screenpos ',a-$8000)
		end
	end
end;

function peek2(a:address):word;
begin
	peek2 := peek(a)+peek(a+1)*256 
end;

procedure poke2(a:address; b:word);
begin
	poke(a,lo(b));
	poke(a+1,hi(b))
end;

function peekX(a: address): word;
begin
	if w then peekX := peek2(a) else peekX := peek(a)
end;

procedure pokeX(a: address; b: word);
begin
	if w then poke2(a,b) else poke(a,b)
end; 

function fetch: byte;
begin
	fetch := peek(IP); inc(IP);
	debug('----fetching '+hexStr(fetch,2))
end;

function fetch2: word;
begin
	fetch2 := peek2(IP); inc(IP,2);
	debug('----fetching '+hexStr(fetch2,4))
end;

function fetchX: word;
begin
	if w then fetchx := fetch2 else fetchx := fetch
end;

function getReg(r: octed): byte;
begin
	if r<4 	then getReg := lo(RX[r])
			else getreg := hi(RX[r-4])
end;

procedure setReg(r: octed; b: byte);
begin
	if r<4 	then RX[r] := hi(RX[r])*256+b
			else RX[r-4] := b*256+lo(RX[r-4]) 
end;

function getReg2(r: octed): word;
begin
	getreg2 := RX[r]
end;

procedure setReg2(r: octed;b: word);
begin
	RX[r] := b 
end;

function getRegX(r: octed): word;
begin
	if w then getregX := getReg2(r) else getRegX := getReg(r)
end;

procedure setRegX(r: octed;b: word);
begin
	if w then setReg2(r,b) else setreg(r,b)
end;


function readRMX(m: boolean; a: address):word;
begin
	if m then readRMX := peekX(a) else readRMX := getregX(a)
end;

procedure writeRMX(m: boolean; a: address; b: word); 
begin
	if m then pokeX(a,b) else setRegX(a,b)
end;

procedure writeLoc(l: location);
begin
	with l do writeRMX(memory,aORi,content)
end;

// -------------- memory mode methods ------------------

procedure modRM;
// reads MRM byte
// sets mode (=the way rm is exploited)
// sets sreg: select general register (in G memory mode) or segment register
// sets rm: select general register or memory (in E memory mode)
var MrM: byte;
begin
	debug('---executing modRm');
	MrM := fetch;
	mode := MrM >> 6;
	sreg := (MrM and %00111000) >> 3;
	rm := MrM and %00000111;
	debug('------modRm '+hexstr(MrM,2)+' '+binstr(MrM,8)+'  '+
			'mode='+hexStr(mode,1)+' sreg='+hexStr(sreg,1)+' rm='+hexStr(rm,1))
end;


function mm_G: location;
// The reg field of the ModR/M byte selects a general register.
var oper: location;
begin
	debug('---executing mm_G');
	debug ('*** warning *** check for byte/word operations');	
	oper.memory := false;
	oper.aORi := sreg;
	oper.content := getRegX(sreg);
	debug('------register '+hexStr(sreg,1)+' read');
	mm_G := oper
end;

function mm_E: location;
// A ModR/M byte follows the opcode and specifies the operand. The operand is either a general­
// purpose register or a memory address. If it is a memory address, the address is computed from a
// segment register and any of the following values: a base register, an index register, a displacement.
// d = 1 data moves from operand specified by R/M field to operand specified by REG field
// d = 0 data moves from operand specified by REG field to operand specified by R/M field

var oper: location;
begin
	debug('---executing mm_E');
	debug('*** warning *** check word/byte operations');
	case mode of
	0:	begin
			oper.memory := true;
			case rm of
			1: begin
					oper.aORi:= RX[BX]+RX[DI];
					oper.content := peekX(oper.aORi);
			   end;
			6: begin //direct addressing
				// what in EI mode ? what is fetched first ??? < imm last. corrected in mm_EI
					oper.aORi := fetch2;
					oper.content := peekX(oper.aORi);
					debug('----------direct addressing');
					debug('----------address='+hexstr(oper.aORi,4));
					debug('----------value='+hexStr(oper.content,4))
			   end;
			7: begin
					oper.aORi := RX[BX];
					oper.content := peekX(oper.aORi)
			   end;
			else
				error('mode=0, rm value not yet implemented')
			end
		end;
//  1: + 8 bit signed displacement		
	2:	begin
			oper.memory := true;
			case rm of
			5:	begin
					oper.aORi := RX[DI]+fetch2; //16 unsigned displacement
					oper.content := peekX(oper.aORi)
				end;
			7:  begin
					oper.aORi := RX[BX]+fetch2; //16 unsigned displacement
					oper.content := peekX(oper.aORi)
				end
			else
				error('mode=2, rm value not yet implemented')
			end
		end;
	3: 	begin
			oper.memory := false;
			oper.aORi := rm;
			oper.content := getRegX(rm);
			debug('------register '+hexStr(rm,1)+' read');
		end;
	else
		error('mode '+intToStr(mode)+' of Ew not yet implemented')
	end;
	mm_E := oper
end;

function mm_I: location;
begin
	debug('---executing mm_I');
	if w
		then if d=0 	then mm_I.content := fetch2
						else mm_I.content := int8(fetch)
		else mm_I.content := fetch;
	debug('------imm val read is '+hexStr(mm_I.content,4))
end;

procedure mm_EI;
begin
	modRM;
	oper1 := mm_E;
	oper2 := mm_I;
end;

procedure mm_EG;
begin
	modRM;
	if d=0  then begin oper1 := mm_E; oper2 := mm_G end
			else begin oper1 := mm_G; oper2 := mm_E end;
end;

procedure mm_AI;
begin
	oper1.memory := false;
	oper1.aORi := 0;
	oper1.content := getRegX(0);
	debug('----------address='+hexstr(oper1.aORi,4));
	debug('----------value='+hexStr(oper1.content,4));
	oper2 := mm_I
end;

procedure writeback;
begin
	with oper1 do
	 begin
		debug('--executing writeBack');
		debug(hexStr(ord(memory),1));
		debug(hexStr(aORi,4));
		debug(hexStr(content,4));		
//		writeRMX(aORi,content)
		if w 
			then
				if memory 	then poke2(aORi,content)
							else RX[aORi]:=content
			else
				if memory 	then poke(aORi,content)
							else 
								if aORi<4 	then RX[aORi] := hi(RX[aORi])*256+content
											else RX[aORi-4] := content*256+lo(RX[aORi-4])
	 end			
//	error ('writeBack under construction');
end;

// -------------------------- instructions -------------------

procedure i_Jcond;
// fetch next byte
// if condition ok then add to IP as two's complement
var b: byte;
	cc: 0..$F;
begin
	debug('--executing Jcond');
	b := fetch;
	cc := IR and %1111;
	case cc of
		2:if FC=1 then IP := IP + int8(b); //JB, JC
		4:if FZ=1 then IP := IP + int8(b); //JZ
		5:if FZ=0 then IP := IP + int8(b); //JNZ
		6:if (FC=1) or (FZ=1) then IP := IP + int8(b); //JBE
		7:if (FC=0) and (FZ=0) then IP := IP + int8(b); // JA, JNBE
		9:if FS=0 then IP := IP + int8(b); //JNS
		else error('JCond not implemented for condition '+hexstr(cc,1))
	end 
end;

procedure i_HLT;
begin
	debug('--executing HLT');
	writeln;writeln('*** program terminated by HLT instruction ***');
	writeln('--- In the ''codegolf'' program this probably means');
	writeln('--- there is some logical error in the emulator');
	writeln('--- or the program reached the end without error');
	writeln('bye');
	display;
	halt
end;

procedure i_MOV;
begin
	debug('--executing MOV EG');
	debug('------'+hexStr(oper1.aORi,4)+' '+hexStr(oper1.content,4));
	debug('------'+hexStr(oper2.aORi,4)+' '+hexStr(oper2.content,4));
	oper1.content := oper2.content;	
	debug('------'+hexStr(oper1.aORi,4)+' '+hexStr(oper1.content,4));
	writeBack
//	writeRMX(oper1.memory,oper1.aORi,oper1.content) // both solutions work
end;

procedure i_XCHG;
var t: word; 
begin
		debug('--executing XCHG EG');
		t := oper1.content;
		oper1.content := oper2.content;
		oper2.content := t;
		writeLoc(oper1);
		writeLoc(oper2)
end;

procedure i_XCHG_RX_AX;
var T: word;
begin
	debug('--executing XCHG RX AX');
	T := RX[AX];
	RX[AX] := RX[IR and %111];
	RX[IR and %111] := T

end;

procedure i_MOV_RX_Iw;
begin 
	debug('--executing MOV Rw ,Iw');
	RX[IR and %111] := fetch2 
end;

procedure i_MOV_R8_Ib;
var r: 0..7;
	b: byte;
begin
	debug('--executing MOV Rb ,Ib');
	b := fetch;
	r := IR and %111;
	if r<4 	then RX[r] := hi(RX[r])*256+b
			else RX[r-4] := b*256+lo(RX[r-4]) 
end;



procedure i_PUSH_RX;
begin
	debug('--executing PUSH RX');
	dec(RX[SP],2); //SP:=SP-2
	poke2(RX[SP],RX[IR and %111]) //poke(SP,RX)	
end;

procedure i_POP_RX;
begin
	debug('--executing POP RX');
	RX[IR and %111] := peek2(RX[SP]); //RX := peek(SP)
	inc(RX[SP],2); //SP:=SP+2
end;

procedure i_JMP_Jb;
var b: byte;
begin
	debug('--executing JMP Jb');	
	b := fetch;
	IP:=IP+int8(b)
end;

procedure i_CALL_Jv;
var w: word;
begin
	debug('--executing CALL Jv');	
	w := fetch2;
	dec(RX[SP],2); //SP:=SP-2	
	poke2(RX[SP],IP);
	IP:=IP+int16(w);
	inc(calldept)
end;

procedure i_RET;
begin
	debug('--executing RET');
	IP := peek2(RX[SP]);
	inc(RX[SP],2); //SP:=SP+2
	dec(calldept)
end;



procedure i_XOR;
begin
	debug('--executing XOR');
	if w=false then error('XOR is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));	
	oper1.content:=oper1.content xor oper2.content;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	FZ:=ord(oper1.content=0);
	FS:=ord(oper1.content>=$8000);
	FC:=0;
	writeback
end;

procedure i_OR;
begin
	debug('--executing OR');
//	if w=false then error('OR is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));	
	oper1.content:=oper1.content or oper2.content;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
	FC:=0;
	writeback
end;

procedure i_AND;
begin
	debug('--executing AND');
//	if w=false then error('AND is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));	
	oper1.content:=oper1.content and oper2.content;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
	FC:=0;
	writeback
end;

procedure i_ADD;
var T: Dword;
begin
	debug('--executing ADD');
//	if w=false then error('ADD is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	T := oper1.content + oper2.content;
	if w then FC := ord(T>$FFFF)
		 else FC := ord(T>$FF);
	oper1.content := T;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
	writeback
end;

procedure i_ADC;
var T: Dword;
begin
	debug('--executing ADC');
	if w=false then error('ADC is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	T := oper1.content + oper2.content + FC;
	FC := ord(T>$FFFF);
	oper1.content := T;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	FZ:=ord(oper1.content=0);
	FS:=ord(oper1.content>=$8000);
	writeback
end;

procedure i_SUB;
var T: Dword;
begin
	debug('--executing SUB');
	if w=false then error('SUB is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	T := oper1.content - oper2.content;
	FC := ord(T>$FFFF);
	oper1.content := T;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	FZ:=ord(oper1.content=0);
	FS:=ord(oper1.content>=$8000);
	writeback
end;

procedure i_SBB;
var T: Dword;
begin
	debug('--executing SBB');
	if w=false then error('SBB is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	T := oper1.content - oper2.content - FC;
	FC := ord(T>$FFFF);
	oper1.content := T;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	FZ:=ord(oper1.content=0);
	FS:=ord(oper1.content>=$8000);
	writeback
end;

procedure i_CMP;
var T: Dword;
begin
	debug('--executing CMP');
//	if w=false then error('CMP is nyi for byte operations - carry not OK');	
//	FC:=ord(oper1.content<oper2.content);
	T:=oper1.content-oper2.content;
	if w then FC := ord(T>$FFFF)
		 else FC := ord(T>$FF);
	oper1.content:=T;
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	// the difference is written in the debug statement but is not written back !
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
end;

procedure i_INC;
begin
	debug('--executing INC');
//	if w=false then error('INC is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	inc(oper1.content);
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
	// FC unchanged
	writeback
end;

procedure i_DEC;
begin
	debug('--executing DEC');
//	if w=false then error('DEC is nyi for byte operations');
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	dec(oper1.content);
	debug('------'+hexStr(oper1.content,4)+' '+hexStr(oper2.content,4));
	if w then FZ:=ord(oper1.content=0)
		 else FZ:=ord(lo(oper1.content)=0);
	if w then FS:=ord(oper1.content>=$8000)
		 else FS:=ord(oper1.content>=$80);
	// FC unchanged
	writeback
end;

procedure i_INC_RX;
var r: 0..7;
begin
	debug('--executing INC RX');
	r := IR and %111;
	inc(RX[r]);
	FZ:=ord(RX[r]=0);
	FS:=ord(RX[r]>=$8000)
	// FC unchanged
end;

procedure i_DEC_RX;
var r: 0..7;
begin
	debug('--executing DEC RX');
	r := IR and %111;
	dec(RX[r]);
	FZ:=ord(RX[r]=0);
	FS:=ord(RX[r]>=$8000)
	// FC unchanged
end;
// ------------------ special instructions --------------

procedure GRP1;
// GRP1 instructions use modRM byte
// sreg selects instruction
// one operand selected by rm in mm_E
// other operand is Immediate:
//   d bit (s in doc) is used as sign bit
//   s = 1 one byte of immediate data is present which
//   must be sign-extended to produce a 16-bit operand
//   s = 0 two bytes of immediate data are present 
//   w bit selects word or byte
begin
	debug('-executing GRP1');
	case sreg of
	0:i_ADD;
	1:i_OR;
	2:i_ADC;
	4:i_AND;
	5:i_SUB;
	7:i_CMP;
	else
		error('subInstruction GRP1 number '+intToStr(sreg)+' is not yet implemented')
	end
end;

procedure GRP4;
begin
	debug('-executing GRP4 Eb');
	modRM;
	oper1 := mm_E;
	case sreg of
	0:i_INC;
	1:i_DEC;
	else
		error('subInstruction GRP4 number '+intToStr(sreg)+' is not yet implemented')
	end
end;

begin //main
	writeln('+-----------------------------------------------+');
	writeln('| emulator for 8086/8088 subset as requested in |');
	writeln('| codegolf challenge                            |');
	writeln('| (c)2019 by ir. Marc Dendooven                 |');
	writeln('| V0.2 DEV                                      |');
	writeln('+-----------------------------------------------+');	
	writeln;
	load;
	IP := 0;
	RX[SP] := $100;
	while IP < segEnd do begin //fetch execute loop
		mon;
		IR := fetch; // IR := peek(IP); inc(IP)
		inc(cnt);
		debug(intToStr(cnt)+'> fetching instruction '+hexstr(IR,2)+' at '+hexstr(IP-1,4));
		w := boolean(IR and %1);
		d := (IR and %10) >> 1;
		case IR of
		$00..$03: begin mm_EG; i_ADD end;	
		$04,$05: begin mm_AI; i_ADD end;
		$08..$0B: begin mm_EG; i_OR end;
		$18..$1B: begin mm_EG; i_SBB end;
		$20..$23: begin mm_EG; i_AND end;
		$28..$2B: begin mm_EG; i_SUB end;
		$30..$33: begin mm_EG; i_XOR end;
		$38..$3B: begin mm_EG; i_CMP end;
		$3C,$3D: begin mm_AI; i_CMP end; //error('$3C - CMP AL Ib - nyi');
		$40..$47: i_INC_RX;
		$48..$4F: i_DEC_RX;
		$50..$57: i_PUSH_RX; 
		$58..$5F: i_POP_RX;
		$72,$74,$75,$76,$77,$79: i_Jcond; // $70..7F has same format with other flags
		$80..$83: begin mm_EI; GRP1 end;
		$86..$87: begin mm_EG; i_XCHG end;	
		$88..$8B: begin mm_EG; i_MOV end; 
		$90: debug('--NOP');
		$91..$97: i_XCHG_RX_AX; 
		$B0..$B7: i_MOV_R8_Ib;
		$B8..$BF: i_MOV_RX_Iw;
		$C3: i_RET;
		$C6,$C7: begin d := 0; mm_EI; i_MOV end; //d is not used as s here... set to 0
		$E8: i_CALL_Jv; 
		$EB: i_JMP_Jb;
		$F4: i_HLT;
		$F9: begin debug('--executing STC');FC := 1 end;
		$FE: GRP4;
		else
			error('instruction is not yet implemented')
		end
	end;
	writeln;
	error('debug - trying to execute outside codesegment')
end.

		(*		-Quickly-
83h is the sign-extended _word_ form..  3h, sw both set
82h is the sign-extended _byte_ form..  2h, s set w clear.
* 
d position MAY be replaced by "s" bit
s = 1 one byte of immediate data is present which
muct be sign-extended to produce a 16-bit
operand
s = 0 two bytes of immediate are present
*)
