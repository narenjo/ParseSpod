package parseSpod.parse;

import datetime.DateTime;

/**
 * ...
 * @author Thomas Byrne
 */
abstract ParseDate(String)
{

	public function new(timestamp:String) 
	{
		this = timestamp;
	}

	@:to
	public function toDate():Date{
		return DateTime.fromString(this).getDate();
	}
	@:to
	public function toFloat():Float{
		return DateTime.fromString(this).getTime() * 1000;
	}
	@:from
	static public function fromDate(date:Date){
		if(date == null){
			return null;
		}
		return new ParseDate(DateTime.fromDate(date).format("%FT%T.000Z"));
	}
	@:from
	static public function fromDynamic(date:Dynamic){
		if(Type.typeof(date) == Type.ValueType.TObject){
			return new ParseDate(date.iso);
		}
		return new ParseDate(date);
	}
}