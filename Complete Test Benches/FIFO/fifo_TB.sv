/////////////////////   Transaction class   ///////////////////////// 

class transaction; 

rand bit wr,rd;
rand bit [7:0] data_in;

bit full,empty;
bit [7:0] data_out;

constraint wr_rd {
    rd != wr;
    wr dist{0:/50 , 1:/50};
    rd dist{0:/50 , 1:/50};
}

constraint data_const {
    data_in > 1;
    data_in < 9;
}


    function void display(input string tag);
        $display("[%0s] : WR = %0b \t RD = %0b \t DATA_WR = %0d \t DATA_RD = %0d \t FULL = %0b \t EMPTY = %0b \t @ %0t",tag,wr,rd,data_in,data_out,full,empty,$time);
    endfunction

    function transaction copy();
        copy = new();
        copy.wr = this.wr;
        copy.rd = this.rd;
        copy.data_in = this.data_in;

        copy.full = this.full;
        copy.empty = this.empty;
        copy.data_out = this.data_out;
    endfunction
endclass


////////////////////    Generator   ////////////////////////////////////

class generator;

mailbox #(transaction) mbx;
transaction tr;

int count = 0;
event next; 
event done;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction

    task main();
        repeat(count)
            begin
              assert(tr.randomize) else $error("Randomization failed at %0t",$time);
                mbx.put(tr.copy);
                tr.display("GEN");
              @(next);
            end
        
        -> done;
    endtask

endclass
//////////////////////  Interface   ////////////////////////////////////////////////////////////////////////////////////

interface fifo_if;

logic clock,rd,wr;      //inputs 
logic [7:0] data_in;
logic rst;

logic full,empty;
logic [7:0] data_out;                   //outputs 

endinterface


/////////////////////////// Driver Class ///////////////////////////////////////////////////////////////////////////////
class driver;

virtual fifo_if fif;

mailbox #(transaction) mbx;
transaction data_container;


    function new(mailbox #(transaction) mbx);
            this.mbx = mbx;
        endfunction
    
    task reset();   //  Active HIGH reset
        fif.rst <= 1'b1;

        fif.rd <= 1'b0;
        fif.wr <= 1'b0;
        fif.data_in = 0;

        repeat (5) @(posedge fif.clock);

        fif.rst <= 1'b0;
        $display("[DUT] RESET DONE");

    endtask

    task main();

        forever begin
            mbx.get(data_container); //GET from the mailbox and place INTO the data_container

            data_container.display("DRV");

            fif.rd <= data_container.rd;    //Triggering the interface with values from the generator
            fif.wr <= data_container.wr;
            fif.data_in <= data_container.data_in;

            repeat(2) @(posedge fif.clock); // ONLY 2 CLOCKS SPECIFICALLY FOR FIFO. Not the same for all DUT
        end
    
     endtask



endclass

/////////// Monitor Class   //////////////////////////////////////////////////////////////////////////////

class monitor;

virtual fifo_if fif;

mailbox #(transaction) mbx;
event next;
transaction tr;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task main();
        tr = new();

        forever begin
            repeat(2) @(posedge fif.clock);

            tr.wr = fif.wr;
            tr.rd = fif.rd;
            tr.data_in = fif.data_in;
            tr.data_out = fif.data_out;
            tr.full = fif.full;
            tr.empty = fif.empty;

            mbx.put(tr);
            tr.display("MON");
        end
    endtask

endclass

//////////////////////////////  Scoreboard Class    /////////////////////////////////////////////////////////////////////

class scoreboard;

mailbox #(transaction) mbx;
transaction tr;

event next;

bit [7:0] data_in[$];   //Queue to store data from write operations
bit [7:0] temp;         // data read from queue 

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction



    task main();
        forever begin
            mbx.get(tr);
            tr.display("SCO");

            if(tr.wr == 1'b1) begin
                data_in.push_front(tr.data_in);
                $display("[SCO] DATA STORED IN QUEUE :%0d",tr.data_in);
            end

            if(tr.rd == 1'b1) begin         //Since its a FIFO we KNOW any time there's a read operation we want the data from the END of the queue
                if(tr.empty == 1'b0)begin

                    temp = data_in.pop_back();

                    if(temp == tr.data_out) 
                        $display("DATA MATCH");
                    else
                        $display("DATA MISMATCH");
                end 

                else
                    $display("FIFO IS EMPTY");
            end 

            ->next;
            $display("----------------------------------------------------------------------------------------------------------------------");
        end
    
    endtask
endclass

////////////////////////////////////////////////    Environment Class   //////////////////////////////////////////////////

class environment;

generator gen;
driver drv;

monitor mon;
scoreboard sco;

event nextgs;                   //event that will work with generator and scoreboard to call next stimulus 

mailbox #(transaction) gdmbx;   // generator and driver mailbox
mailbox #(transaction) msmbx;   // monitor and scoreboard mailbox

virtual fifo_if fif;

    function new(virtual fifo_if fif);

        gdmbx = new();
        gen = new(gdmbx);
        drv = new(gdmbx);

        msmbx = new();
        mon = new(msmbx);
        sco = new(msmbx);

        this.fif = fif;
        drv.fif = this.fif;
        mon.fif = this.fif;

        gen.next = nextgs;
        sco.next = nextgs;
    endfunction


    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.main();
            drv.main();
            mon.main();
            sco.main();
        join_any

    endtask

    task post_test();
        wait(gen.done.triggered);
        $finish();
    endtask

    task main();
        pre_test();
        test();
        post_test();
    endtask

endclass






///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////                            ///////////////////////////////////////////////////////////
/////////////////////////////////////////        TEST BENCH TOP      ///////////////////////////////////////////////////////////
/////////////////////////////////////////                            ///////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module tb;

fifo_if fif();

fifo DUT(                       //instantiate DUT and connecting it to our interface
    .clock(fif.clock),
    .rd(fif.rd),
    .wr(fif.wr),
    .full(fif.full),
    .empty(fif.empty),
    .data_in(fif.data_in),
    .data_out(fif.data_out),
    .rst(fif.rst)
);

initial begin
    fif.clock <= 0;
end 

always #10 fif.clock <= ~fif.clock;

environment env;


initial begin
   env = new(fif);
   env.gen.count = 20;
   env.main();
end 

initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
end

endmodule