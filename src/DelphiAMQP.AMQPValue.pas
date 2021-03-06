// Copyright 2018 Felipe Caputo
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

unit DelphiAMQP.AMQPValue;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

type
  EAMQPParserException = class(Exception);


  TAMQPValueType = class
  private
    FValueType: Char;
    FValue: TBytes;
    FAMQPTable: TObjectDictionary<string, TAMQPValueType>;
//    FFieldArray: TList<TAMQPValueType>;
    FFloatPrecision: Byte;
    FBitOffset: Byte;

    procedure GetScalarValue(var Dest; const Size: Integer);
    procedure SetScalarValue(const Source; const Size: Integer);

    procedure ReadValue(const AStream: TBytesStream; const ASize: Integer);
    procedure ParseShortString(const AStream: TBytesStream);
    procedure ParseLongString(const AStream: TBytesStream);
    procedure ParseAMQPTable(const AStream: TBytesStream);
    procedure ParseAMQPFieldValuePair(const AStream: TBytesStream);
    procedure ParseByteArray(const AStream: TBytesStream);
    procedure ParseFieldArray(const AStream: TBytesStream);
    procedure ParseBit(const AStream: TBytesStream);

    function GetAsString: string;
    procedure SetAsString(const AValue: string);
    procedure SetShortString(const AValue: string);
    procedure SetLongString(const AValue: string);

    function GetAsByte: Byte;
    procedure SetAsByte(const Value: Byte);

    function GetAsWord: Word;
    procedure SetAsWord(const AValue: Word);
    function GetAsUInt32: UInt32;
    procedure SetAsUInt32(const Value: UInt32);
    function GetAsInt32: Int32;
    procedure SetAsInt32(const Value: Int32);
    function GetAsInt64: Int64;
    procedure SetAsInt64(const Value: Int64);
    function GetAsInt8: Int8;
    procedure SetAsInt8(const Value: Int8);
    function GetAsDecimal: Double;
    procedure SetAsDecimal(const AValue: Double);
    function GetAsBoolean: Boolean;
    procedure SetAsBoolean(const Value: Boolean);

    procedure PrepareData(const AStream: TBytesStream);
    procedure PreprareFieldTable();
    procedure PrepareBitValue(const AStream: TBytesStream);

    function GetBitMask(): Byte;
  public
    const
      Bit = '1';
      Bool = 't';
      ShortShortInt = 'b';
      ShortShortUInt = 'B';
      ShortInt = 's';
      ShortUInt = 'u';
      LongInt = 'I';
      LongUInt = 'i';
      LongLongInt = 'l';
//      LongLongUInt = 'l';
      Float = 'f';
      _Double = 'd';
      DecimalValue = 'D';
      ShortString = 'Z';
      LongString = 'S';
      FieldArray = 'A';
      Timestamp = 'T';
      FieldTable = 'F';
      ByteArray = 'x';
      NoValue = 'V';

    constructor Create(const AValueType: Char = TAMQPValueType.NoValue);
    destructor Destroy; override;

    procedure Parse(const AType: Char; const AStream: TBytesStream); overload;
    procedure Parse(const AStream: TBytesStream); overload;
    procedure Write(AStream: TBytesStream);

    property ValueType: Char read FValueType write FValueType;
    property FloatPrecision: Byte read FFloatPrecision write FFloatPrecision;
    property Data: TBytes read FValue;
    property BitOffset: Byte read FBitOffset write FBitOffset;

    //Get typed values
    property AsBoolean: Boolean read GetAsBoolean write SetAsBoolean;
    property AsString: string read GetAsString Write SetAsString;
    property AsByte: Byte read GetAsByte Write SetAsByte;
    property AsInt8: Int8 read GetAsInt8 write SetAsInt8;
    property AsWord: Word read GetAsWord write SetAsWord;
    property AsUInt32: UInt32 read GetAsUInt32 write SetAsUInt32;
    property AsInt32: Int32 read GetAsInt32 write SetAsInt32;
    property AsInt64: Int64 read GetAsInt64 write SetAsInt64;
    property AsDecimal: Double read GetAsDecimal write SetAsDecimal;
    property AsAMQPTable: TObjectDictionary<string,TAMQPValueType> read FAMQPTable;
  end;

implementation

uses
  DelphiAMQP.Util.Helpers, System.DateUtils, System.Math;

{ TAMQPValueType }

const
  sINVALID_STREAM = 'Invalid stream';

destructor TAMQPValueType.Destroy;
begin
  FreeAndNil(FAMQPTable);
  inherited;
end;

function TAMQPValueType.GetAsBoolean: Boolean;
var
  Mask: Byte;
begin
  if FValueType = TAMQPValueType.Bit then
  begin
    Mask := (1 shl (7 -  FBitOffset));
    Exit(FValue[0] and Mask <> 0);
  end;

  Result := FValue[0] <> 0;
end;

function TAMQPValueType.GetAsByte: Byte;
begin
  Result := FValue[0];
end;

function TAMQPValueType.GetAsDecimal: Double;
var
  precision: Byte;
  temp: TBytes;
  value: UInt32;
begin
  precision := FValue[0];
  SetLength(temp, 4);
  AMQPMoveEx(FValue[1], temp, 0, SizeOf(UInt32));
  Move(temp[0], value, SizeOf(UInt32));
  Result := value / Power(10, precision);
end;

function TAMQPValueType.GetAsInt32: Int32;
begin
  GetScalarValue(Result, SizeOf(Int32));
end;

function TAMQPValueType.GetAsInt8: Int8;
begin
  GetScalarValue(Result, SizeOf(Int8));
end;

function TAMQPValueType.GetAsString: string;
var
  offset: Byte;
begin
  offset := IfThen(TAMQPValueType.ShortString = FValueType, 1, 4);
  Result := TEncoding.ANSI.GetString(FValue, offset, Length(FValue) - offset);
end;

function TAMQPValueType.GetAsUInt32: UInt32;
begin
  GetScalarValue(Result, SizeOf(UInt32));
end;

function TAMQPValueType.GetAsInt64: Int64;
begin
  GetScalarValue(Result, SizeOf(UInt64));
end;

procedure TAMQPValueType.Parse(const AType: Char; const AStream: TBytesStream);
begin
  case AType of
    TAMQPValueType.Bit: ParseBit(AStream);
    TAMQPValueType.Bool, TAMQPValueType.ShortShortInt, TAMQPValueType.ShortShortUInt: ReadValue(AStream, 1);
    TAMQPValueType.ShortInt, TAMQPValueType.ShortUInt: ReadValue(AStream, 2);
    TAMQPValueType.LongInt, TAMQPValueType.Float, TAMQPValueType.LongUInt: ReadValue(AStream, 4);
    TAMQPValueType.LongLongInt, TAMQPValueType._Double, TAMQPValueType.Timestamp: ReadValue(AStream, 8);
    TAMQPValueType.DecimalValue: ReadValue(AStream, 5);
    TAMQPValueType.ShortString: ParseShortString(AStream);
    TAMQPValueType.LongString: ParseLongString(AStream);
    TAMQPValueType.FieldTable: ParseAMQPTable(AStream);
    TAMQPValueType.ByteArray: ParseByteArray(AStream);
    TAMQPValueType.FieldArray: ParseFieldArray(AStream);
    else
     Exit;
  end;
end;

procedure TAMQPValueType.ParseAMQPFieldValuePair(const AStream: TBytesStream);
var
  fieldName, fieldValue: TAMQPValueType;
  valueType: Char;
begin
  fieldName := TAMQPValueType.Create(TAMQPValueType.ShortString);
  try
    fieldName.Parse(AStream);
    AStream.Read(valueType, 1);

    fieldValue := TAMQPValueType.Create(valueType);
    fieldValue.Parse(AStream);
    FAMQPTable.Add(fieldName.GetAsString, fieldValue);
  finally
    fieldName.Free;
  end;
end;

procedure TAMQPValueType.ParseAMQPTable(const AStream: TBytesStream);
var
  tableSize: UInt32;
  endPos: Int64;
begin
  tableSize := AStream.AMQPReadLongUInt;
  endPos := AStream.Position + tableSize;

  while AStream.Position < endPos do
    ParseAMQPFieldValuePair(AStream);
end;

procedure TAMQPValueType.ParseBit(const AStream: TBytesStream);
begin
  if FBitOffset <> 0 then
    AStream.Position := Pred(AStream.Position);

  ReadValue(AStream, 1);
end;

procedure TAMQPValueType.ParseByteArray(const AStream: TBytesStream);
var
  size: Int32;
begin
  size := AStream.AMQPReadLongInt;
  AStream.Read(FValue, size);
end;

procedure TAMQPValueType.ParseFieldArray(const AStream: TBytesStream);
//var
//  size: Integer;
begin
  //TODO: !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
end;

procedure TAMQPValueType.ParseLongString(const AStream: TBytesStream);
var
  Size: Cardinal;
begin
  Size := AStream.AMQPReadLongUInt;
  AStream.Position := AStream.Position - SizeOf(UInt32);
  ReadValue(AStream, Size + SizeOf(UInt32));
end;

procedure TAMQPValueType.ParseShortString(const AStream: TBytesStream);
var
  stringSize: TBytes;
begin
  SetLength(stringSize, 1);
  if AStream.Read(stringSize, 1) <> 1 then
    raise EAMQPParserException.Create(sINVALID_STREAM);

  AStream.Position := Pred(AStream.Position);
  ReadValue(AStream, stringSize[0] + 1);
end;

procedure TAMQPValueType.PrepareBitValue(const AStream: TBytesStream);
var
  lastValue: Byte;
begin
  if FBitOffset <> 0 then
  begin
    //Must read previous writen bit
    AStream.Position := Pred(AStream.Position);
    AStream.Read(lastValue, 1);
  end
  else
    lastValue := 0;

  FValue[0] :=  lastValue or (GetBitMask and IfThen(FValue[0]>0, 255, 0));

  if FBitOffset <> 0 then
    AStream.Position := Pred(AStream.Position);
end;

procedure TAMQPValueType.PrepareData(const AStream: TBytesStream);
begin
  if FValueType = TAMQPValueType.FieldTable then
    PreprareFieldTable
  else if FValueType = TAMQPValueType.Bit then
    PrepareBitValue(AStream);
end;

procedure TAMQPValueType.PreprareFieldTable;
var
  TempStream: TBytesStream;
  KeyValue: TPair<string, TAMQPValueType>;
  TempField: TAMQPValueType;
  Size: UInt32;
begin
  TempField := nil;
  TempStream := TBytesStream.Create();
  try
    TempField := TAMQPValueType.Create(TAMQPValueType.ShortString);
    for KeyValue in FAMQPTable.ToArray() do
    begin
      TempField.AsString := KeyValue.Key;
      TempField.Write(TempStream);
      TempStream.Write(KeyValue.Value.ValueType, 1);
      KeyValue.Value.Write(TempStream);
    end;

    Size := TempStream.Size;
    SetLength(FValue, 4 + Size);
    AMQPMoveEx(Size, FValue, 0, SizeOf(UInt32));
    TempStream.Position := 0;
    TempStream.Read(FValue, 4, Size);
  finally
    FreeAndNil(TempStream);
    FreeAndNil(TempField);
  end;
end;

procedure TAMQPValueType.ReadValue(const AStream: TBytesStream; const ASize: Integer);
begin
  SetLength(FValue, ASize);

  if AStream.Read(FValue, ASize) <> ASize then
    raise EAMQPParserException.Create(sINVALID_STREAM);
end;

procedure TAMQPValueType.SetAsBoolean(const Value: Boolean);
begin
  SetLength(FValue, 1);

  if FValueType = TAMQPValueType.Bit then
  begin
    FValue[0] := (IfThen(Value, 1, 0) shl (7 - FBitOffset));
    Exit;
  end;

  FValue[0] := IfThen(Value, 1, 0);
end;

procedure TAMQPValueType.SetAsByte(const Value: Byte);
begin
  SetLength(FValue, SizeOf(Byte));
  FValue[0] := Value;
end;

procedure TAMQPValueType.SetAsDecimal(const AValue: Double);
var
  value: UInt32;
  seed: Double;
begin;
  //Double is not so precise so we need to add an extra value after expected precision to make it
  //return the real integer value
  seed := 1 / Power(10, FFloatPrecision + 2);
  value := Trunc( (AValue + seed) * Power(10, FFloatPrecision));
  SetLength(FValue, 5);
  FValue[0] := FloatPrecision;
  AMQPMoveEx(value, FValue, 1, SizeOf(UInt32));
end;

procedure TAMQPValueType.SetAsInt32(const Value: Int32);
begin
  SetScalarValue(Value, SizeOf(Int32));
end;

procedure TAMQPValueType.SetAsInt8(const Value: Int8);
begin
  SetScalarValue(Value, SizeOf(Int8));
end;

procedure TAMQPValueType.SetAsString(const AValue: string);
begin
  case ValueType of
    TAMQPValueType.ShortString: SetShortString(AValue);
    TAMQPValueType.LongString: SetLongString(AValue);
  else
    raise EAMQPParserException.Create('Field is not a string type.');
  end;
end;

procedure TAMQPValueType.SetAsUInt32(const Value: UInt32);
begin
  SetScalarValue(Value, SizeOf(UInt32));
end;

procedure TAMQPValueType.SetAsInt64(const Value: Int64);
begin
  SetScalarValue(Value, SizeOf(UInt64));
end;

procedure TAMQPValueType.Write(AStream: TBytesStream);
begin
  PrepareData(AStream);
  AStream.Write(FValue, Length(FValue));
end;

constructor TAMQPValueType.Create(const AValueType: Char);
begin
  FValueType := AValueType;
  FFloatPrecision := 2;
  SetLength(FValue, 1);
  FValue[0] := 0;
  FAMQPTable := TObjectDictionary<string,TAMQPValueType>.Create([doOwnsValues]);
end;

procedure TAMQPValueType.Parse(const AStream: TBytesStream);
begin
  Self.Parse(FValueType, AStream);
end;

procedure TAMQPValueType.SetScalarValue(const Source; const Size: Integer);
begin
  SetLength(FValue, Size);
  AMQPMoveEx(Source, FValue, 0, Size);
end;

procedure TAMQPValueType.SetShortString(const AValue: string);
var
  stringSize: Byte;
begin
  if Length(AValue) > 255 then
    raise EAMQPParserException.Create('Shortstring has more than 255 chars.');

  stringSize := Length(AValue);

  SetLength(FValue, 1+ stringSize);
  Move(stringSize, FValue[0], 1);
  Move(TEncoding.ANSI.GetBytes(AValue)[0], FValue[1], stringSize);
end;

procedure TAMQPValueType.SetLongString(const AValue: string);
var
  stringSize: UInt32;
begin
  stringSize := Length(AValue);

  SetLength(FValue, 4 + stringSize);
  AMQPMoveEx(stringSize, FValue, 0, SizeOf(UInt32));
  Move(TEncoding.Ansi.GetBytes(AValue)[0], FValue[4], stringSize);
end;

function TAMQPValueType.GetAsWord: Word;
begin
  GetScalarValue(Result, 2);
end;

function TAMQPValueType.GetBitMask: Byte;
begin
  Result := (1 shl (FBitOffset));
end;

procedure TAMQPValueType.GetScalarValue(var Dest; const Size: Integer);
var
  temp: TBytes;
begin
  SetLength(temp, Size);
  AMQPMoveEx(FValue[0], temp, 0, Size);
  Move(temp[0], Dest, Size);
end;

procedure TAMQPValueType.SetAsWord(const AValue: Word);
begin
  SetScalarValue(AValue, SizeOf(Word));
end;

end.
