(* emulator for 8086/8088 subset as requested in
https://codegolf.stackexchange.com/questions/4732/emulate-an-intel-8086-cpu
(c)2019 by ir. Marc Dendooven *)
 
program ed8086;
uses sysutils;

const memSize = $9000; 

var mem: array[0..memSize-1] of byte;
	IP,segEnd,op1,op2: word;
	IR: byte;
	mode: 0..3;
	sreg:0..7;
	rm:0..7;
	regs:array[0..7] of word; //AX,CX,DX,BX,SP,BP,SI,DI
	C,Z,S: 0..1;
	
function peek(a:word):byte;
begin
	peek := mem[a]
end;

function peek2(a:word):word;
begin
	peek2 := peek(a)+peek(a+1)*256 
end;

procedure poke(a:word;b:byte);
begin
	mem[a]:=b
end;

procedure poke2(a,b:word);
begin
	poke(a,lo(b));
	poke(a+1,hi(b))
end;
	
procedure error(s: string);
begin
	writeln;writeln;
	writeln('ERROR: ',s);
	writeln('program aborted');
	writeln;
	writeln('IP=',hexstr(IP-1,4),' IR=',hexstr(IR,2));
	halt
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
	writeln;
	writeln('IP=',hexstr(IP,4));
	writeln('AX=',hexstr(regs[0],4),' BX=',hexstr(regs[3],4),' CX=',hexstr(regs[1],4),' DX=',hexstr(regs[2],4));
	writeln('SP=',hexstr(regs[4],4),' BP=',hexstr(regs[5],4),' SI=',hexstr(regs[6],4),' DI=',hexstr(regs[7],4));
	writeln('C=',C,' Z=',Z,' S=',S);
//	writeln;writeln('push ENTER to continue');
//	readln
end;

procedure modRM;
var MrM: byte;
begin
	writeln('executing modRm');
	MrM := peek(IP);inc(IP);
	mode := MrM >> 6;
	sreg := (MrM and %00111000) >> 3;
	rm := MrM and %00000111;
	writeln (hexstr(MrM,2),' ',binstr(MrM,8),'  ',
			'mode=',mode,' sreg=',sreg,' rm=',rm)
end;

procedure Ew;
begin
	writeln('executing Ew');
	case mode of
	3: begin op1 := regs[rm]; writeln('op1:=REG ',rm,' (',hexstr(op1,4),')' ) end
	else
		error('mode '+intToStr(mode)+' of Ew not yet implemented')
	end
end;

procedure Iw;
begin
	writeln('executing Iw');
	op2:=peek2(IP);writeln('op2:=imm_w',' (',hexstr(op2,4),')');
	inc(IP,2)
end;

procedure wEw;
begin
	error('subInstruction wEw is not yet implemented')
end;

procedure Jb;
begin
	writeln('executing Jb');
	op1 := peek(IP);inc(IP)
end;

procedure JZ;
begin
	writeln('executing JZ');
	if Z=1 then ip := ip + ShortInt(op1)
end;

procedure CMP;
var H: cardinal;
begin
	writeln('executing CMP');
	H:=op1-op2;
	op1:=H;
	C:=ord(H<=$FFFF);
	Z:=ord(op1=0);
	S:=ord(op1>=$8000)
end;

procedure GRP1;
begin
	writeln('executing GRP1');
	case sreg of
	7:CMP
	else
		error('subInstruction GRP1 number '+intToStr(sreg)+' is not yet implemented')
	end
end;



begin //main
	writeln('+-----------------------------------------------+');
	writeln('| emulator for 8086/8088 subset as requested in |');
	writeln('| codegolf challenge                            |');
	writeln('| (c)2019 by ir. Marc Dendooven                 |');
	writeln('+-----------------------------------------------+');	
	writeln;
	load;
	
	// check output with codegolf file with xxd -g 1 codegolf at terminal -> OK !
	IP := 0;
	while IP < segEnd do begin
		mon;
		IR := peek(IP); inc(IP);
		writeln; writeln('executing instruction ',hexstr(IR,2),' at ',hexstr(IP-1,4));
		case IR of
		$81: begin modRM;Ew;Iw;GRP1;if sreg <> 7 then wEw end;
		$74: begin Jb;JZ end;
		$F4: begin writeln;writeln('program terminated by HLT instruction');halt end
		else
			error('instruction is not yet implemented')
		end
	end;
	writeln;
	error('debug - trying to execute outside codesegment')
end.
